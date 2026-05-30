# frozen_string_literal: true

module Atlas
  class Configuration
    DEFAULT_URL = 'http://localhost:8080'
    DEFAULT_TIMEOUT = 5

    # Atlas tools this client knows how to gate. Mirrors Atlas's service
    # capabilities (geocoding, map matching, ...) so usage can be limited to
    # a subset — e.g. batch geocoding only.
    KNOWN_TOOLS = %i[geocoding map_matching].freeze

    attr_accessor :url, :api_key, :timeout
    attr_reader :enabled_tools

    def initialize
      @url = ENV.fetch('ATLAS_API_URL', DEFAULT_URL)
      @api_key = ENV.fetch('ATLAS_API_KEY', nil)
      @timeout = positive_timeout(ENV.fetch('ATLAS_API_TIMEOUT', DEFAULT_TIMEOUT))
      self.enabled_tools = tools_from_env
    end

    def enabled_tools=(tools)
      @enabled_tools = normalize_tools(tools)
    end

    def tool_enabled?(tool)
      enabled_tools.include?(tool.to_sym)
    end

    private

    def tools_from_env
      raw = ENV.fetch('ATLAS_ENABLED_TOOLS', nil)
      return KNOWN_TOOLS.dup if raw.nil? || raw.strip.empty?

      raw.split(',').map(&:strip).reject(&:empty?)
    end

    def normalize_tools(tools)
      symbols = Array(tools).map { |tool| tool.to_s.strip.to_sym }
      unknown = symbols - KNOWN_TOOLS
      raise ArgumentError, "unknown atlas tool(s): #{unknown.join(', ')}" if unknown.any?

      symbols
    end

    def positive_timeout(value)
      timeout = value.to_i
      timeout.positive? ? timeout : DEFAULT_TIMEOUT
    end
  end
end
