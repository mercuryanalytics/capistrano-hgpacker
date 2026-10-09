# frozen_string_literal: true

require "open3"

# Runs `cap --dry-run` against spec/fixtures/app in a subprocess, so each run gets a
# fresh Rake application. Dry-run swaps SSH for SSHKit's printer backend: commands
# are logged rather than executed, and every `capture` returns "" (no file, package,
# manifest, or stale master on any host).
module Cap
  APP = File.expand_path("../fixtures/app", __dir__)
  GEMFILE = File.expand_path("../../Gemfile", __dir__)
  RUNS = {} # rubocop:disable Style/MutableConstant -- memo shared across examples

  Result = Struct.new(:output) do
    # host => [command, ...] in the order run on that host
    def commands
      output.scan(%r{Running (?:/usr/bin/env )?(.*) as \w+@(\S+)$}).each_with_object(Hash.new {|h, k| h[k] = [] }) do |(command, host), hosts|
        hosts[host] << command
      end
    end

    def all_commands
      output.scan(%r{Running (?:/usr/bin/env )?(.*) as \w+@\S+$}).flatten
    end

    def executed_tasks
      output.scan(%r{^\*\* Execute (\S+)}).flatten
    end
  end

  def self.run(*args)
    RUNS[args] ||= begin
      output, status = Open3.capture2e({ "BUNDLE_GEMFILE" => GEMFILE }, "bundle", "exec", "cap", *args, "--dry-run", chdir: APP)
      raise "cap #{args.join(' ')} failed:\n#{output}" unless status.success?

      Result.new(output.gsub(%r{\e\[[0-9;]*m}, ""))
    end
  end
end
