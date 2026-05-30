# frozen_string_literal: true

require 'zlib'

class DemoData::PointsSeeder
  FIXTURE = Rails.root.join('lib/assets/demo_data.json.gz').freeze

  def initialize(user, import, anchor)
    @user = user
    @import = import
    @anchor = anchor
  end

  def call
    fixture = Zlib::GzipReader.open(FIXTURE) { |gz| Oj.load(gz.read) }
    seed_ts = Time.iso8601(fixture['seed_date']).to_i
    delta = @anchor.to_i - seed_ts
    now = Time.current

    rows = fixture['features'].map do |feature|
      props = feature['properties']
      lat = props['latitude'].to_f
      lon = props['longitude'].to_f
      {
        user_id: @user.id,
        import_id: @import.id,
        timestamp: props['timestamp'].to_i + delta,
        lonlat: "SRID=4326;POINT(#{lon} #{lat})",
        altitude: props['altitude'],
        velocity: props['velocity'],
        accuracy: props['accuracy'],
        vertical_accuracy: props['vertical_accuracy'],
        battery: props['battery'],
        battery_status: props['battery_status'],
        tracker_id: 'demo',
        raw_data: {},
        inrids: [],
        in_regions: [],
        geodata: {},
        created_at: now,
        updated_at: now
      }
    end

    Point.insert_all(rows, returning: false)
    backfill_country_ids
  end

  private

  def backfill_country_ids
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE points
      SET country_id = countries.id
      FROM countries
      WHERE points.import_id = #{@import.id.to_i}
        AND points.country_id IS NULL
        AND ST_Intersects(countries.geom, points.lonlat::geometry)
    SQL
  end
end
