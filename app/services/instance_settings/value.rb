# frozen_string_literal: true

module InstanceSettings
  # The answer to "what is this setting, and who decided it?". The source is as
  # load-bearing as the value: an admin page has to render a Pinned setting
  # read-only and name the variable holding it rather than accept input it would
  # discard.
  class Value
    SOURCES = %i[env stored default].freeze

    attr_reader :key, :value, :source, :env_var

    def initialize(key:, value:, source:, env_var:)
      unless SOURCES.include?(source)
        raise ArgumentError, "unknown source #{source.inspect}, expected one of #{SOURCES.inspect}"
      end

      @key = key
      @value = value
      @source = source
      @env_var = env_var
    end

    def pinned?
      source == :env
    end

    def stored?
      source == :stored
    end
  end
end
