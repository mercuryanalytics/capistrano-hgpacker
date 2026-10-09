# frozen_string_literal: true

namespace :hgpacker do
  task :service_defaults do
    set :hgpacker_services, {}
    set :hgpacker_default_services, lambda {
      app = fetch(:application)
      {
        "passenger@#{app}" => { roles: :web, verb: "reload-or-restart", in: :sequence, wait: 5 },
        "resque-pool@#{app}" => { roles: :resque, verb: "reload-or-restart" },
        "resque-pool-watchdog@#{app}.timer" => { roles: :resque, verb: "start" },
        # Generated from zram-generator.conf, so it has no [Install] section to enable.
        "systemd-zram-setup@zram0" => { roles: :all, verb: "start", enable: false }
      }
    }
  end
  after "load:defaults", "hgpacker:service_defaults"

  desc "Enable each configured service and apply its verb (reload-or-restart, start, ...)"
  task :restart do
    services = Capistrano::Hgpacker::Settings.merge(fetch(:hgpacker_default_services), fetch(:hgpacker_services))
    services.each do |unit, spec|
      on release_roles(*Capistrano::Hgpacker::Settings.roles(spec)), **spec.slice(:in, :wait) do
        execute :sudo, :systemctl, :enable, unit if spec.fetch(:enable, true)
        execute :sudo, :systemctl, spec.fetch(:verb, "reload-or-restart"), unit
      end
    end
  end
end

namespace :deploy do
  after :publishing, :restart
end
after "deploy:restart", "hgpacker:restart"
