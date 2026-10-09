# frozen_string_literal: true

module Capistrano
  module Hgpacker
    module Settings
      module_function

      # The gem's defaults overlaid with the app's entries; an app entry set to nil
      # removes the default of the same name.
      def merge(defaults, overrides)
        defaults.merge(overrides || {}).compact
      end

      def roles(spec)
        Array(spec.fetch(:roles, :all)).map(&:to_sym)
      end

      def applies_to?(spec, host_roles)
        roles = roles(spec)
        roles.include?(:all) || roles.intersect?(host_roles.map(&:to_sym))
      end
    end
  end
end
