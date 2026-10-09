# frozen_string_literal: true

RSpec.describe Capistrano::Hgpacker::Settings do
  describe ".merge" do
    let(:defaults) { { "a" => { source: "a" }, "b" => { source: "b" } } }

    it "lets an app entry replace the default of the same name" do
      expect(described_class.merge(defaults, "a" => { source: "mine" })["a"]).to eq(source: "mine")
    end

    it "lets an app entry of nil remove the default" do
      expect(described_class.merge(defaults, "b" => nil).keys).to eq(["a"])
    end

    it "appends new app entries" do
      expect(described_class.merge(defaults, "c" => {}).keys).to eq(%w[a b c])
    end
  end

  describe ".applies_to?" do
    it "applies to every host when roles is :all or absent" do
      expect(described_class.applies_to?({}, [:web])).to be(true)
      expect(described_class.applies_to?({ roles: :all }, [])).to be(true)
    end

    it "applies only to hosts holding one of the roles" do
      expect(described_class.applies_to?({ roles: %i[resque cron] }, %i[app cron])).to be(true)
      expect(described_class.applies_to?({ roles: :resque }, %i[web app])).to be(false)
    end
  end
end
