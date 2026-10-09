# frozen_string_literal: true

RSpec.describe "hgpacker tasks", type: :task do
  def installs(commands)
    commands.filter_map {|c| c[%r{^sudo install .* (\S+)$}, 1] }
  end

  describe "deploy hooks" do
    let(:tasks) { Cap.run("production", "deploy", "--trace").executed_tasks }

    def position(task) = tasks.index(task) || raise("#{task} did not run")

    it "checks for stale resque masters before the deploy starts" do
      expect(position("hgpacker:resque:check_stale")).to be < position("deploy")
    end

    it "sets the host up right after deploy:check, before any release is created" do
      expect(position("hgpacker:setup")).to be > position("deploy:check")
      expect(position("hgpacker:setup")).to be < position("deploy:started")
      expect(position("hgpacker:required_packages")).to be < position("hgpacker:host_files")
    end

    it "restarts services through deploy:restart after publishing" do
      expect(position("deploy:restart")).to be > position("deploy:publishing")
      expect(position("hgpacker:restart")).to be > position("deploy:restart")
      expect(position("hgpacker:restart")).to be < position("deploy:finished")
    end
  end

  context "with an app that uses every setting" do
    let(:setup) { Cap.run("production", "hgpacker:setup").commands }
    let(:restart) { Cap.run("production", "hgpacker:restart") }

    it "installs the app's packages on every host, after an apt-get update" do
      %w[aws0 aws1].each do |host|
        apt = setup[host].grep(%r{apt-get})
        expect(apt.first).to eq("sudo apt-get update -qq")
        expect(apt.last).to start_with("sudo env DEBIAN_FRONTEND=noninteractive apt-get install")
        expect(apt.last).to end_with("libvips poppler-utils")
      end
    end

    it "installs resque files only on the resque host, minus the one the app removed" do
      expect(installs(setup["aws0"])).to eq(%w[
                                              /etc/systemd/system/resque-pool@.service
                                              /usr/local/bin/resque-pool-app
                                              /etc/systemd/system/resque-pool-watchdog@.service
                                              /etc/systemd/system/resque-pool@talaria.service.d/10-memory.conf
                                              /etc/systemd/system/caduceus@.service
                                              /etc/hgpacker/talaria.manifest
                                            ])
      expect(installs(setup["aws1"])).to eq(%w[/etc/systemd/system/caduceus@.service /etc/hgpacker/talaria.manifest])
    end

    it "installs the wrapper executable and everything else 0644 root:root" do
      expect(setup["aws0"]).to include(a_string_matching(%r{^sudo install -D -m 0755 -o root -g root \S+ /usr/local/bin/resque-pool-app$}))
      expect(setup["aws0"]).to include(a_string_matching(%r{^sudo install -D -m 0644 -o root -g root \S+ /etc/systemd/system/resque-pool@\.service$}))
    end

    it "reloads systemd after the unit files and before writing the manifest" do
      commands = setup["aws0"]
      reload = commands.index("sudo systemctl daemon-reload")
      expect(reload).to be > commands.index {|c| c.end_with?("/etc/systemd/system/caduceus@.service") }
      expect(reload).to be < commands.index {|c| c.end_with?("/etc/hgpacker/talaria.manifest") }
    end

    it "removes the uploaded temp file after each install" do
      uploads = setup["aws0"].filter_map {|c| c[%r{^sudo install .* (hgpacker-\h+) }, 1] }
      expect(uploads).not_to be_empty
      uploads.each {|tmp| expect(setup["aws0"]).to include("rm -f #{tmp}") }
    end

    it "enables and restarts each service on its own roles, defaults first, app additions after" do
      expect(restart.commands["aws0"]).to eq([
                                               "sudo systemctl enable resque-pool@talaria",
                                               "sudo systemctl reload-or-restart resque-pool@talaria",
                                               "sudo systemctl enable caduceus@talaria",
                                               "sudo systemctl reload-or-restart caduceus@talaria"
                                             ])
      expect(restart.commands["aws1"]).to eq([
                                               "sudo systemctl enable passenger@talaria",
                                               "sudo systemctl reload-or-restart passenger@talaria",
                                               "sudo systemctl enable caduceus@talaria",
                                               "sudo systemctl reload-or-restart caduceus@talaria"
                                             ])
      order = restart.all_commands.grep(%r{reload-or-restart}).map {|c| c.split.last }.uniq
      expect(order).to eq(%w[passenger@talaria resque-pool@talaria caduceus@talaria])
    end
  end

  context "with an app that sets nothing" do
    let(:setup) { Cap.run("plain", "hgpacker:setup").commands }
    let(:restart) { Cap.run("plain", "hgpacker:restart").commands }

    it "installs no packages and no files on a web host" do
      expect(setup["web0"]).to be_empty
    end

    it "restarts only passenger" do
      expect(restart["web0"]).to eq(["sudo systemctl enable passenger@talaria", "sudo systemctl reload-or-restart passenger@talaria"])
    end
  end
end
