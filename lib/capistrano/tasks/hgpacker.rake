# frozen_string_literal: true

require "securerandom"
require "stringio"

namespace :hgpacker do
  def hgpacker_host_files
    files = Capistrano::Hgpacker::Settings.merge(fetch(:hgpacker_default_host_files), fetch(:hgpacker_host_files))
    files.map {|destination, spec| Capistrano::Hgpacker::HostFile.build(destination, spec, settings: Capistrano::Configuration.env) }
  end

  # path => { digest:, mode:, owner: } for whichever of `paths` exist on the host.
  def hgpacker_remote_state(paths)
    return {} if paths.empty?

    sha256sum = capture(:sha256sum, *paths, "2>/dev/null", raise_on_non_zero_exit: false)
    stat = capture(:stat, "-c", "'%n %a %U:%G'", *paths, "2>/dev/null", raise_on_non_zero_exit: false)
    Capistrano::Hgpacker::HostFile.parse_remote(sha256sum, stat)
  end

  def hgpacker_install(content, destination, mode: "0644", user: "root", group: "root")
    tmp = "hgpacker-#{SecureRandom.hex(8)}"
    upload! StringIO.new(content), tmp
    execute :sudo, :install, "-D", "-m", mode, "-o", user, "-g", group, tmp, destination
  ensure
    execute :rm, "-f", tmp
  end

  task :defaults do
    set :required_packages, %w[systemd-zram-generator]

    set :hgpacker_manifest_path, -> { "/etc/hgpacker/#{fetch(:application)}.manifest" }

    set :hgpacker_host_files, {}
    set :hgpacker_default_host_files, lambda {
      files = {
        "/etc/systemd/system/resque-pool@.service" => { source: "resque-pool@.service", roles: :resque },
        "/usr/local/bin/resque-pool-app" => { source: "resque-pool-app", mode: "0755", roles: :resque },
        "/etc/systemd/system/resque-pool-watchdog@.service" => { source: "resque-pool-watchdog@.service", roles: :resque },
        "/etc/systemd/system/resque-pool-watchdog@.timer" => { source: "resque-pool-watchdog@.timer", roles: :resque },
        "/etc/systemd/zram-generator.conf" => { source: "zram-generator.conf" }
      }
      if fetch(:hgpacker_resque_memory)
        files["/etc/systemd/system/resque-pool@#{fetch(:application)}.service.d/10-memory.conf"] =
          { source: "resque-pool-memory.conf.erb", roles: :resque }
      end
      files
    }
  end
  after "load:defaults", "hgpacker:defaults"

  desc "Install the configured packages and host files"
  task :setup do
    invoke "hgpacker:required_packages"
    invoke "hgpacker:host_files"
  end

  desc "Install debian packages required by the application"
  task :required_packages do
    packages = fetch(:required_packages)
    next if packages.empty?

    on release_roles :all do
      status = capture(:"dpkg-query", "-W", "-f='${Package} ${Status}\\n'", *packages, "2>/dev/null", raise_on_non_zero_exit: false)
      installed = status.each_line.filter_map {|line| line.split.first if line.include?("install ok installed") }
      missing = packages - installed
      next if missing.empty?

      execute :sudo, :"apt-get", "update", "-qq"
      execute :sudo, :env, "DEBIAN_FRONTEND=noninteractive", :"apt-get", :install, "-qq", "-y",
              "-o", "Dpkg::Progress-Fancy=0",
              "-o", "APT::Color=0",
              "-o", "Dpkg::Use-Pty=0",
              *missing
    end
  end

  desc "Install the configured host files whose content, mode, or owner differ, and record them in the manifest"
  task :host_files do
    files = hgpacker_host_files
    manifest_path = fetch(:hgpacker_manifest_path)

    on release_roles :all do |host|
      mine = files.select {|f| f.for?(host.roles) }
      state = hgpacker_remote_state(mine.map(&:destination))
      changed = mine.reject {|f| f.current?(state[f.destination]) }

      changed.each do |f|
        info "hgpacker: installing #{f.destination}"
        hgpacker_install(f.content, f.destination, mode: f.mode, user: f.user, group: f.group)
      end
      execute :sudo, :systemctl, "daemon-reload" if changed.any?(&:systemd?)

      previous = capture(:cat, manifest_path, "2>/dev/null", raise_on_non_zero_exit: false)
      (Capistrano::Hgpacker::Manifest.parse(previous).keys - mine.map(&:destination)).each do |path|
        warn "hgpacker: #{path} on #{host} is no longer configured; left in place"
      end
      manifest = Capistrano::Hgpacker::Manifest.render(mine)
      hgpacker_install(manifest, manifest_path) unless Capistrano::Hgpacker::Manifest.parse(manifest) == Capistrano::Hgpacker::Manifest.parse(previous)
    end
  end

  desc "Report drift between the configured host files, each host's manifest, and the files on the host"
  task :check do
    files = hgpacker_host_files
    manifest_path = fetch(:hgpacker_manifest_path)
    drifted = Queue.new

    on release_roles :all do |host|
      mine = files.select {|f| f.for?(host.roles) }
      manifest = Capistrano::Hgpacker::Manifest.parse(capture(:cat, manifest_path, "2>/dev/null", raise_on_non_zero_exit: false))
      digests = hgpacker_remote_state(manifest.keys).transform_values {|s| s[:digest] }
      problems = Capistrano::Hgpacker::Manifest.drift(mine, manifest, digests)
      problems.each {|path, problem| warn "hgpacker: #{host} #{path}: #{problem}" }
      drifted << host.to_s if problems.any?
      info "hgpacker: #{host} matches its manifest" if problems.empty?
    end

    raise "hgpacker: drift on #{drifted.size} host(s)" unless drifted.empty?
  end
end

after "deploy:check", "hgpacker:setup"
