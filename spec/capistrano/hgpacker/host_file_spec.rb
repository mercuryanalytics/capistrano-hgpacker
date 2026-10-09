# frozen_string_literal: true

require "tmpdir"

RSpec.describe Capistrano::Hgpacker::HostFile do
  let(:settings) { { application: "talaria", hgpacker_resque_memory: { high: "3G", max: "4G" } } }

  def build(destination, spec, **options)
    described_class.build(destination, spec, settings:, **options)
  end

  describe ".build" do
    it "copies a plain source from the gem verbatim" do
      file = build("/etc/systemd/system/resque-pool@.service", { source: "resque-pool@.service" })
      expect(file.content).to eq(File.read(File.join(Capistrano::Hgpacker::FILES_PATH, "resque-pool@.service")))
      expect(file.content).to include("OOMPolicy=continue")
    end

    it "renders an .erb source against the settings" do
      file = build("/etc/x.conf", { source: "resque-pool-memory.conf.erb" })
      expect(file.content).to eq("[Service]\nMemoryHigh=3G\nMemoryMax=4G\n")
    end

    it "omits limits that are not set" do
      settings[:hgpacker_resque_memory] = { max: "4G" }
      expect(build("/etc/x.conf", { source: "resque-pool-memory.conf.erb" }).content).to eq("[Service]\nMemoryMax=4G\n")
    end

    it "prefers the app's config/hgpacker over the gem's files" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "zram-generator.conf"), "app's own\n")
        file = build("/etc/systemd/zram-generator.conf", { source: "zram-generator.conf" }, search_paths: [dir, Capistrano::Hgpacker::FILES_PATH])
        expect(file.content).to eq("app's own\n")
      end
    end

    it "raises when the source is nowhere on the search path" do
      expect { build("/x", { source: "nope" }) }.to raise_error(ArgumentError, %r{no nope})
    end

    it "defaults to 0644 root:root on every role" do
      file = build("/x", { source: "zram-generator.conf" })
      expect([file.mode, file.user, file.group, file.roles]).to eq(["0644", "root", "root", [:all]])
    end
  end

  describe "#current?" do
    let(:file) { build("/usr/local/bin/resque-pool-app", { source: "resque-pool-app", mode: "0755" }) }
    let(:state) { { digest: file.digest, mode: "755", owner: "root:root" } }

    it "is current when digest, mode, and owner all match" do
      expect(file.current?(state)).to be(true)
    end

    it "is stale when the file is missing, edited, or has the wrong mode or owner" do
      expect(file.current?(nil)).to be(false)
      expect(file.current?(state.merge(digest: "0"))).to be(false)
      expect(file.current?(state.merge(mode: "644"))).to be(false)
      expect(file.current?(state.merge(owner: "deployer:deployer"))).to be(false)
    end
  end

  describe ".parse_remote" do
    it "joins sha256sum and stat output by path, skipping missing files" do
      state = described_class.parse_remote("abc  /etc/a\ndef  /usr/local/bin/b\n", "/etc/a 644 root:root\n/usr/local/bin/b 755 root:root\n")
      expect(state).to eq("/etc/a" => { digest: "abc", mode: "644", owner: "root:root" },
                          "/usr/local/bin/b" => { digest: "def", mode: "755", owner: "root:root" })
      expect(state["/missing"]).to eq({})
    end
  end
end
