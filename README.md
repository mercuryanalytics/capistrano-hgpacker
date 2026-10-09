# capistrano-hgpacker

Capistrano 3 tasks for Rails apps on EC2 hosts built from Mercury's hg-packer AMI.
On every deploy the gem installs the app's apt packages and host files (systemd
units, drop-ins, wrappers), records them in a manifest, and restarts the app's
services.

The AMI and its first-boot `rails-host-init` own everything that does not depend
on the app's code: Ruby, Passenger, `passenger@.service`, the `/var/www/<app>`
skeleton, credentials, logrotate and CloudWatch. This gem owns what changes with
the app.

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

Drop `capistrano/passenger` (or its `passenger_restart_*` settings) and any local
`deploy:restart`; the gem restarts Passenger itself.

## What runs when

| Hook | Task | Does |
|---|---|---|
| `before deploy` | `hgpacker:resque:check_stale` | Fails the deploy if a resque-pool master on a `:resque` host is older than the last release cutover |
| `after deploy:check` | `hgpacker:setup` | `required_packages`, then `host_files` |
| `after deploy:publishing` | `deploy:restart` → `hgpacker:restart` | `systemctl enable` and the configured verb for each service |

`cap <stage> hgpacker:check` compares the configured files, each host's manifest
and the files on the host, prints every disagreement, and fails if there is any.

## Settings

### `:required_packages`

Default `%w[systemd-zram-generator]`. Installed on every host with `apt-get` only
when one is missing. Add to it with `append :required_packages, "libvips"`.

### `:hgpacker_host_files`

A hash of `destination => { source:, mode: "0644", owner: "root:root", roles: :all }`.
`source` is found in the app's `config/hgpacker/` first, then the gem's `files/`.
Only `.erb` sources are rendered, with `fetch` available. A file is installed
only when its digest, mode, or owner differs on the host; `daemon-reload` follows
when anything under `/etc/systemd/` changed.

App entries merge over the gem's defaults by destination. An entry set to `nil`
removes the default. Use a lambda when the destination needs a setting:

```ruby
set :hgpacker_host_files, -> {
  {
    "/etc/systemd/system/caduceus@.service" => { source: "caduceus@.service.erb", roles: :app },
    "/etc/systemd/zram-generator.conf" => nil
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
| `/etc/systemd/zram-generator.conf` (`min(ram / 4, 4096)`, zstd) | all |

### `:hgpacker_resque_memory`

`set :hgpacker_resque_memory, high: "3G", max: "4G"` renders `MemoryHigh`/`MemoryMax`
into the resque-pool drop-in. Either key may be left out.

### `:hgpacker_services`

A hash of `unit => { roles:, verb: "reload-or-restart", enable: true, in:, wait: }`,
merged over the defaults the same way as host files. `in:`/`wait:` go to SSHKit's
`on`. Defaults, in order:

| Unit | Roles | Verb |
|---|---|---|
| `passenger@<app>` | `:web`, in sequence, 5 s apart | `reload-or-restart` |
| `resque-pool@<app>` | `:resque` | `reload-or-restart` |
| `resque-pool-watchdog@<app>.timer` | `:resque` | `start` |
| `systemd-zram-setup@zram0` | all | `start` (not enabled; it is generated) |

If you remove the zram config, remove `systemd-zram-setup@zram0` too.

### `:hgpacker_manifest_path`

Default `/etc/hgpacker/<app>.manifest`, in `sha256sum` format (`sha256sum --check`
reads it). It lists every file the gem installed on that host. A file dropped
from the configuration is reported and left in place, not deleted.

## Resque pool

`resque-pool@<app>` is a oneshot unit: `up` starts a new manager that INTs any
old one (hot swap), and `down` sends QUIT and returns, so in-flight jobs finish.
`OOMPolicy=continue` keeps one OOM-killed worker from draining the pool.
Because a oneshot cannot use `Restart=`, `resque-pool-watchdog@<app>.timer`
reloads the unit every minute when it is active but `resque-pool-app <app> status`
exits 3. Status exit codes: 0 running, 3 not running, 4 no `config/resque-pool.yml`
(nothing expected).

The wrapper finds Ruby through `/usr/local/bin/rails-ruby`, which hg-packer AMIs
from Phase 2 on provide. On an older AMI, create it once:

```sh
sudo ln -s /usr/lib/fullstaq-ruby/versions/3.3.4-jemalloc/bin/ruby /usr/local/bin/rails-ruby
```

## Host contract

The deploy user needs passwordless sudo for at least: `apt-get update`,
`env DEBIAN_FRONTEND=noninteractive apt-get install`, `install` into
`/etc/systemd/system`, `/etc/systemd`, `/usr/local/bin` and `/etc/hgpacker`, and
`systemctl {enable,start,stop,reload,restart,reload-or-restart,daemon-reload}`.
Narrowing `deployer`'s sudoers in hg-packer must keep these.

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```
