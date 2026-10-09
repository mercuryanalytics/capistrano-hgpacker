# capistrano-hgpacker

Glue between a Rails app and the hg-packer AMI it is deployed to with Capistrano.

The AMI provides the baseline every app shares: Ruby, the Postgres client, Passenger
and `passenger@.service`, the `deployer` user, and (via first-boot `rails-host-init`)
the `/var/www/<app>` skeleton, credentials, logrotate and CloudWatch. This gem lets
the app declare what it needs on top of that baseline (system packages, systemd
units and drop-ins for its own processes, which services to restart) and applies
it on every deploy.

Anything every app needs belongs in hg-packer, not in this gem's defaults.

Requires Capistrano 3 and Ruby 3.1+ on the machine running `cap`.

## Install

```ruby
# Gemfile
group :development do
  gem "capistrano-hgpacker", github: "mercuryanalytics/capistrano-hgpacker", tag: "v0.1.0", require: false
end
```

```ruby
# Capfile — after capistrano/deploy, whose tasks it hooks
require "capistrano/deploy"
require "capistrano/hgpacker"
```

The gem restarts Passenger itself through `deploy:restart`. Remove
`require "capistrano/passenger"` from the Capfile: it adds its own action to
`deploy:restart`, so keeping it (even with `passenger_restart_*` settings pointed
at systemd) restarts Passenger twice. Remove any local `deploy:restart` actions
that restart the same services.

### Roles

The gem acts on three roles: `:web` (Passenger), `:resque` (the resque pool), and
every release host (packages, and any host file or service with `roles: :all`).
Give the `resque` role only to hosts that should run workers.


## What runs when

| Hook | Task | Does |
|---|---|---|
| `before deploy` | `hgpacker:resque:check_stale` | Fails the deploy if a resque-pool master on a `:resque` host is older than the last release cutover |
| `after deploy:check` | `hgpacker:setup` | `required_packages`, then `host_files` |
| `after deploy:publishing` | `deploy:restart` → `hgpacker:restart` | `systemctl enable` and the configured verb for each service |

Every task can also be run by hand:

| Task | Does |
|---|---|
| `hgpacker:setup` | `hgpacker:required_packages` then `hgpacker:host_files` |
| `hgpacker:required_packages` | Install any missing `:required_packages` |
| `hgpacker:host_files` | Install changed host files, `daemon-reload` if needed, rewrite the manifest |
| `hgpacker:restart` | Enable each service and apply its verb |
| `hgpacker:resque:check_stale` | The stale-master check |
| `hgpacker:check` | Compare the configured files, each host's manifest, and the files on the host; print every disagreement and fail if there is any |

`hgpacker:check` compares content digests only; a changed mode or owner is not
reported (the next deploy fixes it anyway).

## Settings

### `:required_packages`

The system packages the app needs beyond the AMI's baseline (e.g. `libvips`,
`imagemagick`). Default `[]`. Installed on every release host with `apt-get`, and
only when one is missing (`apt-get update` runs first in that case):

```ruby
append :required_packages, "libvips", "poppler-utils"
```

Packages are never removed; taking one off the list leaves it installed.

### `:hgpacker_host_files`

A hash of `destination => { source:, mode: "0644", owner: "root:root", roles: :all }`.
`source` is an absolute path, or is looked up in the app's `config/hgpacker/`
first, then the gem's `files/`; a source found in neither fails the deploy.
Only `.erb` sources are rendered; they can call `fetch` for any setting. A file is installed
only when its digest, mode, or owner differs on the host; `daemon-reload` follows
when anything under `/etc/systemd/` changed.

App entries merge over the gem's defaults by destination; an app entry set to
`nil` removes the default. Wrap the hash in a lambda when it needs another
setting, such as the app name in a drop-in path:

```ruby
set :hgpacker_host_files, -> {
  {
    "/etc/systemd/system/caduceus@.service" => { source: "caduceus@.service.erb", roles: :app },
    "/etc/systemd/system/passenger@#{fetch(:application)}.service.d/10-env.conf" => { source: "passenger-env.conf", roles: :web },
    "/etc/systemd/system/resque-pool-watchdog@.timer" => nil
  }
}
```

Defaults:

| Destination | Roles |
|---|---|
| `/etc/systemd/system/resque-pool@.service` | `:resque` |
| `/usr/local/bin/resque-pool-app` (0755) | `:resque` |
| `/etc/systemd/system/resque-pool-watchdog@.service` and `.timer` | `:resque` |
| `/etc/systemd/system/resque-pool@<app>.service.d/10-memory.conf`, only when `:hgpacker_resque_memory` is set | `:resque` |

### `:hgpacker_resque_memory`

`set :hgpacker_resque_memory, high: "3G", max: "4G"` installs a drop-in on `:resque`
hosts setting `MemoryHigh`/`MemoryMax` for `resque-pool@<app>`. Either key may be
left out. Unset (the default), no drop-in is installed.

### `:hgpacker_services`

A hash of `unit => { roles: :all, verb: "reload-or-restart", enable: true, in:, wait: }`,
merged over the defaults the same way as host files. `in:`/`wait:` go to SSHKit's
`on` (e.g. `in: :sequence, wait: 5`). Services run one at a time, in order: the
defaults first, then the app's additions; each finishes on all its hosts before
the next starts. Defaults:

| Unit | Roles | Verb |
|---|---|---|
| `passenger@<app>` | `:web`, in sequence, 5 s apart | `reload-or-restart` |
| `resque-pool@<app>` | `:resque` | `reload-or-restart` |
| `resque-pool-watchdog@<app>.timer` | `:resque` | `start` |

```ruby
set :hgpacker_services, -> { { "caduceus@#{fetch(:application)}" => { roles: :app } } }
```

Only `deploy:restart` is hooked. A service that must also stop around migrations
or start again on `deploy:failed` keeps those hooks in the app. Removing a service
from the hash does not stop or disable it on the host.
### `:hgpacker_manifest_path`

Default `/etc/hgpacker/<app>.manifest`, in `sha256sum` format (`sha256sum --check`
reads it). Each deploy rewrites it to list the files configured for that host.
A file dropped from the configuration is left on the host, not deleted; the deploy
that drops it warns once, and after that the manifest no longer mentions it.
Remove such a file by hand.

## Resque pool

`resque-pool@<app>` is a oneshot unit: `up` starts a new manager that INTs any
old one (hot swap), and `down` sends QUIT and returns, so in-flight jobs finish.
`OOMPolicy=continue` keeps one OOM-killed worker from draining the pool.
Because a oneshot cannot use `Restart=`, `resque-pool-watchdog@<app>.timer`
reloads the unit every minute when it is active but `resque-pool-app <app> status`
exits 3. Status exit codes: 0 running, 3 not running, 4 no `config/resque-pool.yml`
(nothing expected).

To use it, an app needs the `resque-pool` gem in its bundle, a
`config/resque-pool.yml`, and the `resque` role on its worker hosts. Logs go to
`shared/log/resque-pool.{stdout,stderr}.log`. Run `resque-pool-app <app> status`
on a host to see the managers.

The wrapper finds Ruby through `/usr/local/bin/rails-ruby`, which hg-packer AMIs
from Phase 2 on provide. On an older AMI, create it once (adjust the Ruby version
to the one installed):

```sh
sudo ln -s /usr/lib/fullstaq-ruby/versions/3.3.4-jemalloc/bin/ruby /usr/local/bin/rails-ruby
```

## Host contract

The deploy user needs passwordless sudo for:

- `apt-get update` and `env DEBIAN_FRONTEND=noninteractive apt-get install`
- `install` into every configured destination: by default `/etc/systemd/system`
  (including `*.service.d/` drop-in directories) and `/usr/local/bin`, plus
  `/etc/hgpacker` for the manifest
- `systemctl daemon-reload`, `systemctl enable`, and each configured verb
  (by default `reload-or-restart` and `start`)

It also needs a writable home directory (files are uploaded there before
`install` moves them) and read access to the installed files (`sha256sum`, `stat`).
Narrowing `deployer`'s sudoers in hg-packer must keep these.

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

The specs cover the plain-Ruby helpers. To check the task wiring without hosts,
point a throwaway Capfile at this gem and run `cap <stage> deploy --dry-run --trace`.
