# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

# Runs files/resque-pool-app under bash with APPS_ROOT pointed at a temp dir and a
# fake `ps` first on PATH, whose output is FAKE_PS.
RSpec.describe "resque-pool-app", type: :task do
  let(:wrapper) { File.join(Capistrano::Hgpacker::FILES_PATH, "resque-pool-app") }
  let(:root) { Dir.mktmpdir }
  let(:app_dir) { File.join(root, "talaria") }
  let(:ps_output) { "" }

  before do
    FileUtils.mkdir_p(File.join(app_dir, "current/config"))
    FileUtils.mkdir_p(File.join(root, "bin"))
    File.write(File.join(root, "bin/ps"), "#!/bin/sh\nprintf '%s' \"$FAKE_PS\"\n")
    File.chmod(0o755, File.join(root, "bin/ps"))
  end

  after { FileUtils.remove_entry(root) }

  def run(*args)
    env = { "APPS_ROOT" => root, "PATH" => "#{root}/bin:#{ENV.fetch('PATH')}", "FAKE_PS" => ps_output }
    output, status = Open3.capture2e(env, "bash", wrapper, *args)
    [output, status.exitstatus]
  end

  def configure_pool
    File.write(File.join(app_dir, "current/config/resque-pool.yml"), "default: 1\n")
  end

  describe "status" do
    context "with a manager running for the app" do
      let(:ps_output) do
        <<~PS
          4321 resque-pool-master[talaria]: managing [4322]
          4322 resque-2.6.0: Waiting for *
          5000 resque-pool-master[thoth]: managing [5001]
        PS
      end

      it "exits 0 and lists only this app's manager" do
        configure_pool
        output, status = run("talaria", "status")
        expect(status).to eq(0)
        expect(output).to include("resque-pool manager(s) for talaria: 4321\n")
      end
    end

    context "with the pool configured but no manager running" do
      let(:ps_output) { "4322 resque-2.6.0: Processing default since 1700000000\n5000 resque-pool-master[thoth]: managing [5001]\n" }

      it "exits 3, which the watchdog acts on" do
        configure_pool
        output, status = run("talaria", "status")
        expect(status).to eq(3)
        expect(output).to include("no resque-pool manager running for talaria")
      end
    end

    context "without a resque-pool.yml" do
      it "exits 4, so the watchdog leaves it alone" do
        output, status = run("talaria", "status")
        expect(status).to eq(4)
        expect(output).to include("no resque-pool.yml")
      end
    end

    it "reports the lock file" do
      configure_pool
      expect(run("talaria", "status").first).to include("lock file: none at #{app_dir}/shared/tmp/pids/resque-pool.lock")
      FileUtils.mkdir_p(File.join(app_dir, "shared/tmp/pids"))
      FileUtils.touch(File.join(app_dir, "shared/tmp/pids/resque-pool.lock"))
      expect(run("talaria", "status").first).to include("(held)")
    end
  end

  describe "up" do
    it "succeeds without starting anything when the app has no resque-pool.yml" do
      output, status = run("talaria", "up")
      expect(status).to eq(0)
      expect(output).to include("nothing to start")
    end
  end

  describe "down" do
    it "succeeds when no manager is running" do
      output, status = run("talaria", "down")
      expect(status).to eq(0)
      expect(output).to include("no running resque-pool manager for talaria")
    end
  end

  it "fails for an app that is not deployed" do
    output, status = run("thoth", "status")
    expect(status).to eq(1)
    expect(output).to include("Application thoth not found")
  end
end
