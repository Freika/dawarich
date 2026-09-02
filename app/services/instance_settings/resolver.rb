# frozen_string_literal: true

module InstanceSettings
  # Decides what an Instance setting is worth right now, and says who decided:
  # the environment pins, a stored row fills in, and the registry backstops.
  #
  # Reads must be cheap and must never break boot. `Point` evaluates
  # `store_geodata?` once per created row, and config/initializers resolve while
  # `assets:precompile` runs in an image build with no database at all — so the
  # read path takes no lock and every database failure degrades to ENV + default
  # rather than raising.
  module Resolver
    class PinnedSettingError < StandardError; end

    # Redis pub/sub is fire-and-forget with no replay, so a message published
    # while this process was reconnecting is simply gone. Without a ceiling on
    # snapshot age that process would serve stale config indefinitely with
    # nothing able to notice.
    SNAPSHOT_TTL = 30.seconds

    # Anything that means "the database cannot answer right now". Each degrades
    # to ENV + default instead of taking the process down.
    DB_UNAVAILABLE = [
      ActiveRecord::StatementInvalid,
      ActiveRecord::NoDatabaseError,
      ActiveRecord::ConnectionNotEstablished,
      PG::ConnectionBad
    ].freeze

    # Not database outages: the row is there but its ciphertext cannot be read —
    # keys rotated, a dump restored with different keys (Decryption), or the
    # encryption keys missing or malformed entirely (Configuration). Both must
    # degrade to unset rather than take down every read, including the admin
    # page an operator would use to fix it.
    UNREADABLE = [
      ActiveRecord::Encryption::Errors::Decryption,
      ActiveRecord::Encryption::Errors::Configuration
    ].freeze

    class << self
      def get(key)
        definition = Registry.fetch(key)
        env_raw = ENV.fetch(definition.env_var, nil)

        return build(definition, definition.coerce(env_raw), :env) if present?(env_raw)

        # Read the snapshot once. Calling `stored` twice lets the subscriber
        # thread's reset!, or the TTL, swap it between the check and the fetch,
        # raising KeyError on a key that was present a moment earlier.
        snapshot = stored
        return build(definition, snapshot.fetch(definition.key), :stored) if snapshot.key?(definition.key)

        build(definition, definition.default, :default)
      end

      def value(key)
        get(key).value
      end

      def pinned?(key)
        get(key).pinned?
      end

      # Writing a pinned key would accept input the environment overrides, which
      # is the behaviour this whole object exists to remove.
      def set(key, new_value)
        definition = Registry.fetch(key)
        if pinned?(definition.key)
          raise PinnedSettingError,
                "#{definition.key} is pinned by #{definition.env_var} and cannot be changed here"
        end

        record = InstanceSetting.find_or_initialize_by(key: definition.key.to_s)
        record.value = new_value
        record.save!
        reset!
        Notifier.publish(definition.key)
        record
      end

      def reset!
        @snapshot = nil
        # Cleared too: otherwise the first transient outage silences every later
        # one for the life of the process, which is exactly when an operator is
        # trying to diagnose it.
        @warned = false
        InstanceSettings.reset_flag_cache!
      end

      private

      # One read fills the whole snapshot; per-key lookups never touch the
      # database. The snapshot is frozen and replaced wholesale rather than
      # mutated, so readers never need a lock.
      # The snapshot is a single frozen object holding both the data and the
      # time it was read, swapped in one assignment. Storing the two separately
      # let a concurrent reset! land between them, leaving a snapshot with no
      # timestamp that the TTL could never expire.
      def stored
        current = @snapshot
        return current[:data] if current && current[:at] > SNAPSHOT_TTL.ago

        data = load_stored
        @snapshot = { data: data, at: Time.current }.freeze
        data
      end

      # Loads row by row so one undecryptable secret degrades to unset instead
      # of blanking every other setting on the instance.
      def load_stored
        InstanceSetting.all.each_with_object({}) do |record, acc|
          definition = safe_definition(record.key)
          next if definition.nil?

          value = read_record(record, definition)
          # Absent, not present-as-nil: an unreadable row must fall through to
          # the registry default rather than report itself as a stored nil.
          next if value.nil?

          acc[definition.key] = value
        end.freeze
      rescue *DB_UNAVAILABLE => e
        warn_once(e)
        {}.freeze
      end

      def read_record(record, definition)
        definition.secret? ? record.value : record[:value]
      rescue *UNREADABLE
        Rails.logger.warn("[InstanceSettings] #{definition.key} cannot be decrypted; treating as unset")
        nil
      end

      def safe_definition(key)
        Registry.fetch(key)
      rescue KeyError
        nil
      end

      def present?(raw)
        !raw.nil? && !raw.to_s.strip.empty?
      end

      def build(definition, resolved, source)
        Value.new(key: definition.key, value: resolved, source: source, env_var: definition.env_var)
      end

      def warn_once(error)
        return if @warned

        @warned = true
        Rails.logger.warn(
          "[InstanceSettings] database unavailable (#{error.class}); " \
          'resolving from environment and defaults only'
        )
      end
    end
  end
end
