lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "capistrano/hgpacker/version"

Gem::Specification.new do |spec|
  spec.name = "capistrano-hgpacker"
  spec.authors = ["Scott Brickner"]
  spec.email = ["scottb@mercuryanalytics.com"]
  spec.version = Capistrano::Hgpacker::VERSION
  spec.summary = "Support tasks for hg-packer"
  spec.homepage = "https://github.com/mercuryanalytics/capistrano-hgpacker"
  spec.license = nil

  spec.required_ruby_version = "~> 3.0"

  spec.files = `git ls-files -z`.split("\x0").reject {|f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{exe}) {|f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "capistrano", "~> 3.0"

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
end
