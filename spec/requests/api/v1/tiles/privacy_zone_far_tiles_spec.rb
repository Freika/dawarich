# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tiles far from every privacy zone', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:zoom) { 12 }
  let(:auth) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    tag = create(:tag, :privacy_zone, user:, privacy_radius_meters: 400)
    place = create(:place, user:, latitude: 52.444, longitude: 13.5, lonlat: 'POINT(13.5 52.444)')
    create(:tagging, tag:, taggable: place)

    track = create(:track, user:, start_at: Time.utc(2026, 1, 1, 10), end_at: Time.utc(2026, 1, 1, 10, 30),
                           original_path: 'LINESTRING(11.57 48.13, 11.58 48.13)')
    [11.57, 11.58].each_with_index do |lon, index|
      create(:point, user:, track:, lonlat: "POINT(#{lon} 48.13)", timestamp: Time.utc(2026, 1, 1, 10, index).to_i)
    end
  end

  def tile_for(lon, lat)
    n = 2**zoom
    rad = lat * Math::PI / 180
    [((lon + 180) / 360 * n).floor, ((1 - (Math.log(Math.tan(rad) + (1 / Math.cos(rad))) / Math::PI)) / 2 * n).floor]
  end

  def executed_sql(&block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements.join("\n")
  end

  def zone_terms?(sql)
    sql.include?('ST_Buffer') || sql.include?('ST_MakePoint(13.5, 52.444)')
  end

  it 'leaves the zone out of point and track tile SQL and out of trip tile clipping' do
    x, y = tile_for(11.575, 48.13)
    trip = create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 2),
                         skip_calculation_enqueue: true)

    sql = executed_sql do
      get "/api/v1/tiles/points/#{zoom}/#{x}/#{y}.mvt", headers: auth
      get "/api/v1/tiles/tracks/#{zoom}/#{x}/#{y}.mvt", headers: auth
    end
    trip_sql = executed_sql { get "/api/v1/tiles/trips/#{trip.id}/#{zoom}/#{x}/#{y}.mvt", headers: auth }

    expect(sql).to include('ST_AsMVT')
    expect(zone_terms?(sql)).to be(false)
    expect(trip_sql).to include('ST_AsMVT')
    expect(trip_sql).not_to include('ST_Buffer')
  end

  it 'clips with the zone in a tile next to it' do
    x, y = tile_for(13.5, 52.444)

    sql = executed_sql { get "/api/v1/tiles/tracks/#{zoom}/#{x}/#{y}.mvt", headers: auth }

    expect(zone_terms?(sql)).to be(true)
  end
end
