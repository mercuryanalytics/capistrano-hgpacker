# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Capistrano 3 plugin gem providing server-setup and deploy tasks for Rails apps running on EC2 hosts built from Mercury's hg-packer images (Passenger under systemd, CloudWatch agent, logrotate). Consumers add it to their Capfile with `require "capistrano/hgpacker"`.

## Commands

There is no Gemfile, Rakefile, or spec suite yet — the only tooling is lint:

```sh
rubocop                      # needs rubocop + rubocop-rspec installed
gem build capistrano-hgpacker.gemspec
```

`spec.files` comes from `git ls-files`, so new files must be committed (or at least staged) before they ship in a built gem.

## Architecture

- `lib/capistrano/hgpacker.rb` is the real entry point: it `load`s every rake file under `lib/capistrano/tasks/`. A new task file does nothing until it is added there. (`lib/capistrano-hgpacker.rb` is empty.)
- `tasks/hgpacker.rake` — the `hgpacker:*` namespace plus a top-level `hgpacker` task that runs the one-time host setup in order: `required_packages` → `check:directories` → `logs` (logrotate + cloudwatch_agent) → `keys`. Defaults are set in `hgpacker:defaults`, hooked `after "load:defaults"`, so consumer `config/deploy*.rb` files can override them with `set`.
- `tasks/restart.rake` — side effect on load: hooks `deploy:restart` (systemctl restart `passenger@<application>`) after `deploy:publishing` for every consumer.
- Helpers `passenger_path` / `credentials_path` are defined with `def` inside the namespace block, which makes them global methods on the Rake DSL, not namespaced.

## Configurable settings

`:required_packages`, `:passenger_path`, `:credentials_path`, `:logrotate_conf_path`, `:cloudwatch_agent_user`, `:cloudwatch_file_path`, `:cloudwatch_group_name`, `:cloudwatch_stream_name`, `:cloudwatch_conf_path`. Remote config files are uploaded to a random temp name in the deploy user's home, then `sudo mv`'d into place and chowned.

## Conventions

Rubocop config (`.rubocop.yml`): double-quoted strings, `%r{}` regexps, `# frozen_string_literal: true`, no block-param spacing (`{|f| ... }`), Metrics and line-length cops disabled.
