# frozen_string_literal: true

module Achievements
  # Retains only disjoint observed intervals, trimming after the qualifying
  # instant. It never stores the raw history in a card or counts devices twice.
  class ObservedTime
    BATCH_SIZE = 2_000
    MAX_GAP = 10.minutes.to_i
    PAIR_CAP = 2.minutes.to_i
    GEOGRAPHIC_TARGET = 10.minutes.to_i
    PARK_TARGET = 30.minutes.to_i

    def initialize(user, dataset: nil, from: nil, to: nil, privacy_zone_masker: nil, prepare_flights: true)
      @user = user
      @dataset = dataset
      @from = from&.to_i || user.points.minimum(:timestamp) || 0
      @through = [to&.to_i || Time.current.to_i, Time.current.to_i].min
      @masker = privacy_zone_masker
      @prepare_flights = prepare_flights
      @buckets = {}
      @previous = {}
      @timezones = {}
      @qualified = {}
      @parks = dataset ? Exploration::Territory.where(dataset_id: dataset.id, kind: 'park').index_by(&:code) : {}
    end

    def call
      ApplicationRecord.transaction do
        if @prepare_flights
          Exploration::FlightEvidence.prepare!(@user, from: Time.zone.at(@from),
to: Time.zone.at(@through))
        end
        each_point do |point|
          current = memberships(point)
          previous = @previous[point['device']]
          if previous && point['timestamp'] > previous[:point]['timestamp'] &&
             point['timestamp'] - previous[:point]['timestamp'] <= MAX_GAP
            (previous[:regions].keys & current.keys).each do |key|
              next unless previous[:regions][key] == current[key]

              add_pair(key, current[key], previous[:point], point)
            end
          end
          @previous[point['device']] = { point: point, regions: current }
        end
      end
      results
    end

    private

    def each_point(&block)
      timestamp = @from
      id = 0
      loop do
        parks = if @dataset
                  'ARRAY(SELECT t.code FROM exploration_territories t ' \
                    "WHERE t.dataset_id=#{@dataset.id} AND t.kind='park' " \
                    'AND t.boundary && points.lonlat::geometry AND ST_Covers(t.boundary,points.lonlat::geometry))'
                else
                  'ARRAY[]::text[]'
                end
        rows = ApplicationRecord.connection.select_all(<<~SQL).to_a
          SELECT points.id,points.timestamp,ST_Y(points.lonlat::geometry) AS latitude,
            ST_X(points.lonlat::geometry) AS longitude,
            COALESCE(NULLIF(s.tracker_id,''),NULLIF(points.tracker_id,''),
                     'source:' || COALESCE(points.source_id,0)::text) AS device,
            (points.anomaly IS DISTINCT FROM TRUE AND (#{Exploration::FlightEvidence.qualifying_sql})) AS eligible,
            to_json(#{parks})::text AS parks
          FROM points LEFT JOIN point_sources s ON s.id=points.source_id
          WHERE points.user_id=#{@user.id} AND points.lonlat IS NOT NULL
            AND points.timestamp >= #{@from} AND points.timestamp <= #{@through}
            AND (points.timestamp,points.id) > (#{timestamp},#{id})
          ORDER BY points.timestamp,points.id LIMIT #{BATCH_SIZE}
        SQL
        break if rows.empty?

        rows.each(&block)
        timestamp, id = rows.last.values_at('timestamp', 'id')
      end
    end

    def memberships(point)
      return {} unless point['eligible']

      lat, lon = point.values_at('latitude', 'longitude')
      return {} if @masker&.in_zone?(lon, lat)

      @timezones.clear if @timezones.size >= 4_096
      zone = @timezones[[lat, lon]] ||= LocationTimezone.call(lat, lon)
      geographic = zone ? GeographicRegions.memberships(lat, lon).index_with { zone } : {}
      JSON.parse(point.fetch('parks', '[]')).each { |key| geographic[key] = @parks.fetch(key).timezone }
      geographic.compact
    end

    def add_pair(key, zone, left, right)
      return if @qualified[key] && left.fetch('timestamp') > @qualified[key] + MAX_GAP

      from = left.fetch('timestamp')
      to = from + [right.fetch('timestamp') - from, PAIR_CAP].min
      while from < to
        local = Time.at(from).in_time_zone(zone)
        midnight = (local.to_date + 1).in_time_zone(zone).to_i
        ending = [to, midnight].min
        bucket = @buckets[[key, zone, local.to_date.iso8601]] ||= []
        merge_interval(bucket, [from, ending, left.fetch('id'), right.fetch('id')], target(key))
        @qualified[key] = [@qualified[key], bucket.last[1]].compact.min if duration(bucket) >= target(key)
        from = ending
      end
    end

    def merge_interval(bucket, interval, needed)
      return if bucket.any? && duration(bucket) >= needed && interval[0] >= bucket.last[1]

      merged = []
      (bucket + [interval]).sort_by(&:first).each do |item|
        if merged.last && item[0] <= merged.last[1]
          merged.last[3] = item[3] if item[1] > merged.last[1]
          merged.last[1] = [merged.last[1], item[1]].max
        else
          merged << item.dup
        end
      end
      count = 0
      merged.each do |item|
        count += item[1] - item[0]
        next if count < needed

        item[1] -= count - needed
        merged = merged.take(merged.index(item) + 1)
        break
      end
      bucket.replace(merged)
    end

    def duration(intervals)
      intervals.sum { |from, to, _left_id, _right_id| to - from }
    end

    def target(key)
      @parks.key?(key) ? PARK_TARGET : GEOGRAPHIC_TARGET
    end

    def results
      @buckets.each_with_object({}) do |((key, zone, day), intervals), result|
        seconds = duration(intervals)
        evidence = { 'seconds' => seconds, 'target' => target(key), 'day' => day, 'timezone' => zone,
                     'at' => Time.at(intervals.last[1]).utc.iso8601,
                     'first_point_id' => intervals.first[2], 'last_point_id' => intervals.last[3] }
        previous = result[key]
        better = previous.nil? ||
                 (previous['seconds'] < target(key) && seconds > previous['seconds']) ||
                 (seconds >= target(key) && previous['seconds'] >= target(key) && evidence['at'] < previous['at'])
        result[key] = evidence if better
      end
    end
  end
end
