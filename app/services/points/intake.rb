# frozen_string_literal: true

module Points
  class Intake
    SLICE_SIZE = 1_000
    MODES = %i[realtime bulk].freeze

    def self.call(user_id:, payloads:, mode: :realtime)
      new(user_id, payloads, mode).call
    end

    def initialize(user_id, payloads, mode)
      raise ArgumentError, "unsupported intake mode: #{mode}" unless MODES.include?(mode)

      @user_id = user_id
      @payloads = payloads
      @mode = mode
    end

    def call
      return [] if usable_payloads.empty?

      upserted = upsert(usable_payloads)
      return [] if upserted.empty?

      bump_points_count(upserted)
      register_arrival(upserted) if mode == :realtime

      upserted
    end

    private

    attr_reader :user_id, :payloads, :mode

    def usable_payloads
      @usable_payloads ||= payloads
                           .compact
                           .reject { |payload| unusable?(payload) }
                           .map { |payload| payload.merge(user_id: user_id) }
                           .uniq { |payload| Point.dedup_key(payload) }
    end

    def unusable?(payload)
      payload[:lonlat].nil? || payload[:timestamp].nil? || Points::NullIsland.lonlat?(payload[:lonlat])
    end

    def upsert(batch)
      batch.each_slice(SLICE_SIZE).flat_map do |slice|
        dimension_resolver.stamp(slice)

        Point.archival_safe_upsert_all(slice, returning: Arel.sql(Point::UPSERT_RETURNING_COLUMNS)) || []
      end
    end

    def register_arrival(upserted)
      Points::AnomalyFilterJob.perform_later(user_id, timestamps.min, timestamps.max) if timestamps.any?
      Tracks::RealtimeDebouncer.new(user_id).trigger
      Tracks::BackfillScheduler.new(user_id, timestamps).call
      Visits::RealtimeDebouncer.new(user_id).trigger
      Points::LiveBroadcaster.new(user_id, upserted, usable_payloads).call
    end

    def bump_points_count(upserted)
      inserted = upserted.count { |row| row['xmax'].to_i.zero? }

      User.update_counters(user_id, points_count: inserted) if inserted.positive?
    end

    def timestamps
      @timestamps ||= usable_payloads.filter_map { |payload| payload[:timestamp]&.to_i }
    end

    def dimension_resolver
      @dimension_resolver ||= Points::DimensionResolver.new
    end
  end
end
