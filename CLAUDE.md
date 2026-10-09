# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Capistrano 3 plugin gem providing server-setup and deploy tasks for Rails apps running on EC2 hosts built from Mercury's hg-packer images (Passenger under systemd, CloudWatch agent, logrotate). Consumers add it to their Capfile with `require "capistrano/hgpacker"`.

## Commands

```sh
bundle install
bundle exec rspec            # specs cover the plain-Ruby helpers only
bundle exec rubocop
gem build capistrano-hgpacker.gemspec
```

`spec.files` comes from `git ls-files`, so new files (including `files/`) must be committed (or at least staged) before they ship in a built gem.

To exercise the rake wiring without hosts, make a throwaway Capfile that requires `capistrano/deploy` then `capistrano/hgpacker`, and run `cap <stage> deploy --dry-run --trace` with `BUNDLE_GEMFILE` pointing at this repo's Gemfile.

## Architecture

Boundary: the hg-packer AMI and its first-boot `rails-host-init` own credentials, logrotate, CloudWatch and the `/var/www/<app>` skeleton. This gem owns only what changes with the app (packages, systemd units/drop-ins, wrappers, service restarts). Don't add tasks that duplicate `rails-host-init`.

- `lib/capistrano/hgpacker.rb` is the real entry point: it requires the helpers and `load`s each rake file under `lib/capistrano/tasks/`. A new task file does nothing until it is added there. (`lib/capistrano-hgpacker.rb` is deliberately empty; Bundler.require loads it in the app.)
- Plain-Ruby logic (merging settings, rendering/locating sources, remote-state parsing, manifest and drift) lives in `lib/capistrano/hgpacker/*.rb` so it can be specced without SSH. Keep the rake files thin.
- `tasks/hgpacker.rake` — defaults, `hgpacker:setup` (`required_packages` + `host_files`, hooked after `deploy:check`), `hgpacker:check`.
- `tasks/services.rake` — `hgpacker:restart`, hooked via `deploy:restart` after `deploy:publishing`.
- `tasks/resque.rake` — `hgpacker:resque:check_stale`, hooked `before :deploy`.
- `files/` — default host-file sources. `resque-pool@.service` and `resque-pool-app` came from thoth's hosts (commit 9ed6cdd); keep later changes to them minimal and deliberate, since thoth's adoption is checked by diffing against that baseline.
- Helpers are `def`s inside namespace blocks, which makes them global methods on the Rake DSL; prefix them `hgpacker_`.
- Defaults are set in tasks hooked `after "load:defaults"`. Host files and services each have a gem default setting (`hgpacker_default_*`) and an app setting (`hgpacker_*`) merged over it by key, with `nil` removing a default.

## Configurable settings

See README.md: `:required_packages`, `:hgpacker_host_files`, `:hgpacker_resque_memory`, `:hgpacker_services`, `:hgpacker_manifest_path`.

## Conventions

Rubocop config (`.rubocop.yml`): double-quoted strings, `%r{}` regexps, `# frozen_string_literal: true`, no block-param spacing (`{|f| ... }`), Metrics and line-length cops disabled.
