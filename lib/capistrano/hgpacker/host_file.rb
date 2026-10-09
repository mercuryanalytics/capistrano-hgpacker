# frozen_string_literal: true

require "digest"
require "erb"

module Capistrano
  module Hgpacker
    FILES_PATH = File.expand_path("../../../files", __dir__)

    # A file rendered locally for installation at `destination` on the host.
    class HostFile
      # Exposes `fetch` (the Capistrano settings) to ERB sources.
      class Context
        def initialize(settings)
          @settings = settings
        end

        def fetch(...)
          @settings.fetch(...)
        end

        def render(template)
          ERB.new(template, trim_mode: "-").result(binding)
        end
      end

      attr_reader :destination, :content, :mode, :owner, :roles

      # Relative sources are found in the app's config/hgpacker first, then the gem's
      # files/. Only `.erb` sources are rendered.
      def self.build(destination, spec, settings:, search_paths: ["config/hgpacker", FILES_PATH])
        source = locate(spec.fetch(:source), search_paths)
        content = File.read(source)
        content = Context.new(settings).render(content) if source.end_with?(".erb")
        new(destination, content, mode: spec.fetch(:mode, "0644"), owner: spec.fetch(:owner, "root:root"), roles: Settings.roles(spec))
      end

      def self.locate(source, search_paths)
        return source if File.absolute_path?(source)

        search_paths.map {|dir| File.join(dir, source) }.find {|path| File.file?(path) } or
          raise ArgumentError, "hgpacker: no #{source} in #{search_paths.join(', ')}"
      end

      # `sha256sum` and `stat -c "%n %a %U:%G"` output → { path => { digest:, mode:, owner: } }
      def self.parse_remote(sha256sum, stat)
        state = Hash.new {|h, k| h[k] = {} }
        sha256sum.each_line do |line|
          digest, path = line.split(" ", 2)
          state[path.strip][:digest] = digest if path
        end
        stat.each_line do |line|
          path, mode, owner = line.split
          state[path].merge!(mode:, owner:) if owner
        end
        state
      end

      def initialize(destination, content, mode:, owner:, roles:)
        @destination = destination
        @content = content
        @mode = mode
        @owner = owner
        @roles = roles
      end

      def digest
        Digest::SHA256.hexdigest(content)
      end

      def user = owner.split(":").first
      def group = owner.split(":").last

      def for?(host_roles)
        Settings.applies_to?({ roles: }, host_roles)
      end

      def systemd?
        destination.start_with?("/etc/systemd/")
      end

      def current?(state)
        !state.nil? && state[:digest] == digest && state[:mode].to_s.to_i(8) == mode.to_i(8) && state[:owner] == owner
      end
    end
  end
end
