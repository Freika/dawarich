# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track tiles around privacy zones' do
  let(:user) { create(:user) }
  let(:zone_lon) { 13.5 }
  let(:zone_lat) { 52.444 }
  let(:masker) { Maps::PrivacyZoneMasker.new(user) }

  before do
    tag = create(:tag, :privacy_zone, user:, privacy_radius_meters: 500)
    place = create(:place, user:, latitude: zone_lat, longitude: zone_lon, lonlat: "POINT(#{zone_lon} #{zone_lat})")
    create(:tagging, tag:, taggable: place)
  end

  def tile_for(lon, lat, zoom)
    n = 2**zoom
    lat_rad = lat * Math::PI / 180
    x = ((lon + 180.0) / 360.0 * n).floor
    y = ((1.0 - (Math.log(Math.tan(lat_rad) + (1 / Math.cos(lat_rad))) / Math::PI)) / 2.0 * n).floor
    { z: zoom, x:, y: }
  end

  def parts(row)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(['SELECT ST_NumGeometries(?::geometry)', row['geom']])
    )
  end

  def track_with_points(*coords)
    track = create(:track, user:, start_at: 2.hours.ago, end_at: 1.hour.ago,
                           original_path: "LINESTRING(#{coords.map { |c| c.join(' ') }.join(', ')})")
    coords.each_with_index do |(lon, lat), index|
      create(:point, user:, track:, lonlat: "POINT(#{lon} #{lat})", timestamp: 2.hours.ago.to_i + (index * 60))
    end
    track
  end

  describe Tracks::VectorTileQuery do
    def rows(**tile)
      described_class.new(scope: user.tracks, privacy_zone_masker: masker, **tile).feature_rows
    end

    it 'cuts a track that crosses the zone into two pieces' do
      track_with_points([13.40, 52.444], [13.60, 52.444])

      row = rows(**tile_for(zone_lon, zone_lat, 10)).sole

      expect(parts(row)).to eq(2)
    end

    it 'cuts tracks in the date-clipped branch too' do
      track_with_points([13.40, 52.444], [13.45, 52.444], [13.55, 52.444], [13.60, 52.444])

      row = described_class.new(
        scope: user.tracks, privacy_zone_masker: masker, clip_points_scope: user.points,
        clip_start_at: 3.hours.ago.to_i, clip_end_at: (2.hours.ago + 150.seconds).to_i,
        **tile_for(zone_lon, zone_lat, 10)
      ).feature_rows.sole

      expect(parts(row)).to eq(2)
    end

    it 'leaves out a track that lies entirely inside the zone' do
      track_with_points([13.4995, 52.444], [13.5005, 52.444])

      expect(rows(**tile_for(zone_lon, zone_lat, 10))).to be_empty
    end

    it 'leaves tracks away from the zone untouched' do
      track_with_points([13.40, 52.60], [13.60, 52.60])

      expect(parts(rows(**tile_for(13.5, 52.60, 10)).sole)).to eq(1)
    end
  end

  describe Tracks::SpeedVectorTileQuery do
    def rows(**tile)
      described_class.new(scope: user.tracks, points_scope: user.points, privacy_zone_masker: masker, **tile)
                     .feature_rows
    end

    it 'cuts a sparse segment that crosses the zone without a point inside it' do
      track_with_points([13.40, 52.444], [13.60, 52.444])

      row = rows(**tile_for(zone_lon, zone_lat, 10)).sole

      expect(parts(row)).to eq(2)
    end

    it 'does not fall back to the raw path for a track entirely inside the zone' do
      track_with_points([13.4995, 52.444], [13.5005, 52.444])

      expect(rows(**tile_for(zone_lon, zone_lat, 10))).to be_empty
    end
  end
end
