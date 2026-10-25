# frozen_string_literal: true

module GeofenceEvents
  class Evaluator
    MAX_ACCURACY_M = 500
    MIN_BAND_M = 50
    HORIZON = 24.hours

    Sample = Struct.new(:ordinal, :timestamp, :longitude, :latitude, :accuracy, keyword_init: true)

    def self.call(user_id:, rows:, payloads:)
      new(user_id, rows, payloads).call
    rescue StandardError => e
      ExceptionReporter.call(e, 'Geofence evaluation failed')
      nil
    end

    def initialize(user_id, rows, payloads)
      @user_id = user_id
      @rows = rows
      @payloads = payloads
    end

    def call
      return unless Place.geofences.exists?(user_id: @user_id)

      store = StateStore.new(user)
      samples = fresh_samples(store.evaluated_at)
      return if samples.empty?

      walk(samples, store.inside_ids & places.keys.to_set)
      store.advance_evaluated_at!(samples.last.timestamp)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
    end

    private

    def user
      @user ||= User.find(@user_id)
    end

    def places
      @places ||= user.places.geofences.index_by(&:id)
    end

    def fresh_samples(evaluated_at)
      accuracy_by_timestamp = @payloads.to_h { |payload| [payload[:timestamp].to_i, payload[:accuracy]] }
      @rows.select { |row| row['xmax'].to_i.zero? }
           .map { |row| sample_for(row, accuracy_by_timestamp) }
           .reject { |sample| sample.accuracy.to_i > MAX_ACCURACY_M }
           .select { |sample| sample.timestamp > [evaluated_at.to_i, HORIZON.ago.to_i].max }
           .sort_by(&:timestamp)
           .each_with_index.map { |sample, index| sample.tap { |s| s.ordinal = index } }
    end

    def sample_for(row, accuracy_by_timestamp)
      timestamp = row['timestamp'].to_i
      Sample.new(timestamp:, longitude: row['longitude'].to_f, latitude: row['latitude'].to_f,
                 accuracy: accuracy_by_timestamp[timestamp]&.to_i)
    end

    def walk(samples, inside)
      proximity = proximity_by_sample(samples)
      samples.each do |sample|
        near = proximity.fetch(sample.ordinal, {})
        (near.select { |_, entered| entered }.keys.to_set - inside).each do |place_id|
          inside << place_id
          record(place_id, :enter, sample)
        end
        (inside - near.keys.to_set).each do |place_id|
          inside.delete(place_id)
          record(place_id, :leave, sample)
        end
      end
    end

    def record(place_id, event_type, sample)
      Record.call(
        user:, place: places.fetch(place_id), event_type:, source: :server_inferred,
        occurred_at: Time.zone.at(sample.timestamp), accuracy_m: sample.accuracy,
        lonlat: "POINT(#{sample.longitude} #{sample.latitude})"
      )
    end

    def proximity_by_sample(samples)
      rows = ActiveRecord::Base.connection.select_rows(proximity_sql(samples))
      rows.each_with_object({}) do |(ordinal, place_id, entered), map|
        (map[ordinal.to_i] ||= {})[place_id.to_i] = ActiveModel::Type::Boolean.new.cast(entered)
      end
    end

    def proximity_sql(samples)
      values = samples.map do |sample|
        accuracy = sample.accuracy&.to_i || 'NULL'
        "(#{sample.ordinal}, #{sample.longitude.to_f}, #{sample.latitude.to_f}, #{accuracy}::integer)"
      end
      place_point = 'COALESCE(places.lonlat, ' \
                    'ST_SetSRID(ST_MakePoint(places.longitude, places.latitude), 4326)::geography)'
      sample_point = 'ST_SetSRID(ST_MakePoint(samples.lon, samples.lat), 4326)::geography'
      <<~SQL.squish
        SELECT samples.ordinal, places.id, ST_DWithin(#{place_point}, #{sample_point}, places.visit_radius, false)
        FROM (VALUES #{values.join(', ')}) AS samples(ordinal, lon, lat, accuracy)
        JOIN places ON places.user_id = #{@user_id.to_i} AND places.geofence
          AND ST_DWithin(#{place_point}, #{sample_point},
                         places.visit_radius + GREATEST(COALESCE(samples.accuracy, 0), #{MIN_BAND_M}), false)
      SQL
    end
  end
end
