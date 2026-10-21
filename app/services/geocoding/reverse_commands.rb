# frozen_string_literal: true

module Geocoding
  module ReverseCommands
    POINT = 'geocoding.reverse_point'
    PLACE = 'geocoding.reverse_place'
    BATCH_SIZE = 100

    module_function

    def forward(record, force:, event_id:)
      type = record.is_a?(Point) ? POINT : PLACE
      return false unless JobOwnership.oban?("command:#{type}")

      JobCommands.forward(type, payload(record, force), event_id:, aggregate_id: record.user_id,
                                                         producer: 'ReverseGeocodingJob')
      true
    end

    def enqueue_points(user_id, ids, force:, producer:)
      ids = force ? clear_dedup_keys(ids) : claim_dedup_keys(ids)
      begin
        ids.each_slice(BATCH_SIZE) do |slice|
          JobCommands.produce(POINT, { 'user_id' => user_id, 'point_ids' => slice, 'force' => force },
                              aggregate_id: user_id, producer:)
        end
      rescue StandardError
        clear_dedup_keys(ids) unless force
        raise
      end
    end

    def payload(record, force)
      return { 'place_id' => record.id } unless record.is_a?(Point)

      { 'user_id' => record.user_id, 'point_ids' => [record.id], 'force' => force ? true : false }
    end

    def claim_dedup_keys(ids)
      Point.claim_geocode_ids(ids)
    end

    def clear_dedup_keys(ids)
      PhoenixClaims.unclaim_all(ids.map { Point.geocode_dedup_key(_1) })
      ids
    end
  end
end
