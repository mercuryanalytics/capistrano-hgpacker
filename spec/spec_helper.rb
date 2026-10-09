# frozen_string_literal: true

require "capistrano/hgpacker/version"
require "capistrano/hgpacker/settings"
require "capistrano/hgpacker/host_file"
require "capistrano/hgpacker/manifest"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) {|c| c.syntax = :expect }
end
