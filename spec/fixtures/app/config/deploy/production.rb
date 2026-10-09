# frozen_string_literal: true

# An app that uses every setting.
server "aws0", user: "deployer", roles: %w[app cron resque]
server "aws1", user: "deployer", roles: %w[web app db]

append :required_packages, "libvips", "poppler-utils"
set :hgpacker_resque_memory, high: "3G", max: "4G"
set :hgpacker_host_files, lambda {
  {
    "/etc/systemd/system/caduceus@.service" => { source: "caduceus@.service.erb", roles: :app },
    "/etc/systemd/system/resque-pool-watchdog@.timer" => nil
  }
}
set :hgpacker_services, lambda {
  {
    "caduceus@#{fetch(:application)}" => { roles: :app },
    "resque-pool-watchdog@#{fetch(:application)}.timer" => nil
  }
}
