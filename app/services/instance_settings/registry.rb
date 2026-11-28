# frozen_string_literal: true

module InstanceSettings
  # Declares every Instance setting the resolver knows about: the variable that
  # pins it, how to read a string into its type, and what it means when nobody
  # has set it. Adding a setting is a line here, not a new code path.
  module Registry
    class Definition
      attr_reader :key, :env_var, :kind, :default, :minimum

      # A setting with no env_var lives only on the admin page; nothing pins it.
      def initialize(key:, kind:, env_var: nil, default: nil, minimum: nil)
        @key = key
        @env_var = env_var
        @kind = kind
        @default = default
        @minimum = minimum
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
        when :integer then at_least_minimum(Integer(raw.to_s.strip, exception: false))
        when :float then Float(raw.to_s.strip, exception: false) || default
        else raise ArgumentError, "unknown kind #{kind.inspect}"
        end
      end

      private

      def at_least_minimum(value)
        return default if value.nil? || (minimum && value < minimum)

        value
      end
    end

    DEFINITIONS = [
      Definition.new(key: :photon_api_host, env_var: 'PHOTON_API_HOST', kind: :string),
      Definition.new(key: :photon_api_key, env_var: 'PHOTON_API_KEY', kind: :secret),
      Definition.new(key: :photon_api_use_https, env_var: 'PHOTON_API_USE_HTTPS', kind: :boolean,
                     default: false),
      Definition.new(key: :photon_api_language, env_var: 'PHOTON_API_LANGUAGE', kind: :string, default: 'en'),
      Definition.new(key: :nominatim_api_host, env_var: 'NOMINATIM_API_HOST', kind: :string),
      Definition.new(key: :nominatim_api_key, env_var: 'NOMINATIM_API_KEY', kind: :secret),
      Definition.new(key: :nominatim_api_use_https, env_var: 'NOMINATIM_API_USE_HTTPS', kind: :boolean,
                     default: true),
      Definition.new(key: :geoapify_api_key, env_var: 'GEOAPIFY_API_KEY', kind: :secret),
      Definition.new(key: :locationiq_api_key, env_var: 'LOCATIONIQ_API_KEY', kind: :secret),
      # Blank means unlimited, so nil is a meaningful default rather than a missing one.
      Definition.new(key: :reverse_geocoding_rps, env_var: 'REVERSE_GEOCODING_RPS', kind: :float),
      Definition.new(key: :store_geodata, env_var: 'STORE_GEODATA', kind: :boolean, default: true),
      # Whole-file importers hold the parsed file in memory: a 256 MiB JSON parses
      # to ~690 MiB with Oj, so 512 fits a 4 GiB worker. A KML DOM amplifies far
      # more, hence its lower bound.
      Definition.new(key: :import_max_file_size_mb, kind: :integer, default: 512, minimum: 1),
      Definition.new(key: :kml_max_file_size_mb, kind: :integer, default: 64, minimum: 1)
    ].index_by(&:key).freeze

    def self.keys
      DEFINITIONS.keys
    end

    def self.fetch(key)
      DEFINITIONS.fetch(key.to_sym)
    end

    # The variables that can pin a setting; settings without one are left out.
    def self.env_vars
      DEFINITIONS.values.filter_map(&:env_var)
    end

    def self.secret_keys
      DEFINITIONS.values.select(&:secret?).map(&:key)
    end
  end
end
