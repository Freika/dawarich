# frozen_string_literal: true

module InstanceSettings
  # Declares every Instance setting the resolver knows about: the variable that
  # pins it, how to read a string into its type, and what it means when nobody
  # has set it. Adding a setting is a line here, not a new code path.
  module Registry
    class Definition
      attr_reader :key, :env_var, :kind, :default

      def initialize(key:, env_var:, kind:, default: nil)
        @key = key
        @env_var = env_var
        @kind = kind
        @default = default
      end

      def secret?
        kind == :secret
      end

      # A blank value means "nobody set this", never zero and never false. The
      # ENV.fetch(...).to_i idiom reads an empty variable as 0, which silently
      # turns an unset timeout into "fail immediately".
      def coerce(raw)
        return default if raw.nil? || raw.to_s.strip.empty?

        case kind
        when :string, :secret then raw.to_s.strip
        when :boolean then raw.to_s.strip == 'true'
        when :integer then Integer(raw.to_s.strip, exception: false) || default
        when :float then Float(raw.to_s.strip, exception: false) || default
        else raise ArgumentError, "unknown kind #{kind.inspect}"
        end
      end
    end

    DEFINITIONS = [
      Definition.new(key: :photon_api_host, env_var: 'PHOTON_API_HOST', kind: :string),
      Definition.new(key: :photon_api_key, env_var: 'PHOTON_API_KEY', kind: :secret),
      Definition.new(key: :photon_api_use_https, env_var: 'PHOTON_API_USE_HTTPS', kind: :boolean,
                     default: false),
      Definition.new(key: :nominatim_api_host, env_var: 'NOMINATIM_API_HOST', kind: :string),
      Definition.new(key: :nominatim_api_key, env_var: 'NOMINATIM_API_KEY', kind: :secret),
      Definition.new(key: :nominatim_api_use_https, env_var: 'NOMINATIM_API_USE_HTTPS', kind: :boolean,
                     default: true),
      Definition.new(key: :geoapify_api_key, env_var: 'GEOAPIFY_API_KEY', kind: :secret),
      Definition.new(key: :locationiq_api_key, env_var: 'LOCATIONIQ_API_KEY', kind: :secret),
      # Blank means unlimited, so nil is a meaningful default rather than a missing one.
      Definition.new(key: :reverse_geocoding_rps, env_var: 'REVERSE_GEOCODING_RPS', kind: :float),
      Definition.new(key: :store_geodata, env_var: 'STORE_GEODATA', kind: :boolean, default: true)
    ].index_by(&:key).freeze

    def self.keys
      DEFINITIONS.keys
    end

    def self.fetch(key)
      DEFINITIONS.fetch(key.to_sym)
    end

    def self.secret_keys
      DEFINITIONS.values.select(&:secret?).map(&:key)
    end
  end
end
