# frozen_string_literal: true

RSpec.describe Capistrano::Hgpacker::Manifest do
  let(:a) { Capistrano::Hgpacker::HostFile.new("/etc/a", "a\n", mode: "0644", owner: "root:root", roles: [:all]) }
  let(:b) { Capistrano::Hgpacker::HostFile.new("/etc/b", "b\n", mode: "0644", owner: "root:root", roles: [:all]) }

  it "renders sha256sum format, sorted by path, and parses it back" do
    text = described_class.render([b, a])
    expect(text).to eq("#{a.digest}  /etc/a\n#{b.digest}  /etc/b\n")
    expect(described_class.parse(text)).to eq("/etc/a" => a.digest, "/etc/b" => b.digest)
  end

  it "parses a missing manifest as empty" do
    expect(described_class.parse("")).to eq({})
  end

  describe ".drift" do
    let(:manifest) { { "/etc/a" => a.digest, "/etc/b" => b.digest } }

    it "reports nothing when config, manifest, and host agree" do
      expect(described_class.drift([a, b], manifest, manifest)).to eq([])
    end

    it "reports each kind of disagreement" do
      c = Capistrano::Hgpacker::HostFile.new("/etc/c", "c\n", mode: "0644", owner: "root:root", roles: [:all])
      edited_a = Capistrano::Hgpacker::HostFile.new("/etc/a", "new\n", mode: "0644", owner: "root:root", roles: [:all])
      problems = described_class.drift([edited_a, c], manifest, "/etc/a" => "hand-edited")
      expect(problems).to contain_exactly(
        ["/etc/a", "configuration changed since the last deploy"],
        ["/etc/a", "changed on the host since it was installed"],
        ["/etc/c", "not installed yet (next deploy installs it)"],
        ["/etc/b", "no longer configured (left in place)"],
        ["/etc/b", "missing from the host"]
      )
    end
  end
end
