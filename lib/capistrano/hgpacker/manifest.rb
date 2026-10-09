# frozen_string_literal: true

module Capistrano
  module Hgpacker
    # The record of what the gem installed on a host, in `sha256sum` format so that
    # `sha256sum --check` (or anything else) can read it.
    module Manifest
      module_function

      def render(files)
        files.sort_by(&:destination).map {|f| "#{f.digest}  #{f.destination}\n" }.join
      end

      def parse(text)
        text.to_s.each_line.to_h {|line| line.chomp.split("  ", 2).reverse }
      end

      # Each [path, problem] where the configured files, the manifest, and the host's
      # current digests (path => digest) disagree.
      def drift(files, manifest, host_digests)
        configured = files.to_h {|f| [f.destination, f.digest] }
        problems = configured.filter_map do |path, digest|
          if !manifest.key?(path) then [path, "not installed yet (next deploy installs it)"]
          elsif manifest[path] != digest then [path, "configuration changed since the last deploy"]
          end
        end
        manifest.each do |path, digest|
          problems << [path, "no longer configured (left in place)"] unless configured.key?(path)
          if host_digests[path].nil? then problems << [path, "missing from the host"]
          elsif host_digests[path] != digest then problems << [path, "changed on the host since it was installed"]
          end
        end
        problems
      end
    end
  end
end
