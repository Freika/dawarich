# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Live map broadcasts around privacy zones' do
  let(:user) { create(:user, settings: { 'live_map_enabled' => true }) }

  before do
    tag = create(:tag, :privacy_zone, user:, privacy_radius_meters: 500)
    place = create(:place, user:, latitude: 52.444, longitude: 13.5, lonlat: 'POINT(13.5 52.444)')
    create(:tagging, tag:, taggable: place)
  end

  def distance_to_zone(geometry_sql)
    ActiveRecord::Base.connection.select_value(
      "SELECT ST_Distance((#{geometry_sql})::geography, ST_SetSRID(ST_MakePoint(13.5, 52.444), 4326)::geography, false)"
    )
  end

  def quoted(value)
    ActiveRecord::Base.connection.quote(value)
  end

  it 'does not broadcast a new point inside the zone' do
    expect { create(:point, user:, lonlat: 'POINT(13.5 52.444)') }
      .not_to have_broadcasted_to(user).from_channel(PointsChannel)
  end

  it 'broadcasts a new point outside the zone' do
    expect { create(:point, user:, lonlat: 'POINT(13.7 52.6)') }
      .to have_broadcasted_to(user).from_channel(PointsChannel)
  end

  it 'sends the created track cut at the zone' do
    payloads = []
    allow(TracksChannel).to receive(:broadcast_to) { |_, payload| payloads << payload }

    create(:track, user:, original_path: 'LINESTRING(13.40 52.444, 13.60 52.444)')

    wkt = payloads.find { |p| p[:action] == 'created' }[:track][:original_path]
    expect(distance_to_zone("ST_GeomFromText(#{quoted(wkt)}, 4326)")).to be >= 500
  end

  it 'does not announce a track that lies entirely inside the zone' do
    expect { create(:track, user:, original_path: 'LINESTRING(13.4995 52.444, 13.5005 52.444)') }
      .not_to have_broadcasted_to(user).from_channel(TracksChannel)
  end

  it 'sends the track GeoJSON update cut at the zone' do
    track = create(:track, user:, original_path: 'LINESTRING(13.40 52.444, 13.60 52.444)')
    payloads = []
    allow(TracksChannel).to receive(:broadcast_to) { |_, payload| payloads << payload }

    track.broadcast_geojson_updated

    geometry = payloads.sole[:track][:geometry]
    expect(geometry[:type]).to eq('MultiLineString')
    expect(distance_to_zone("ST_SetSRID(ST_GeomFromGeoJSON(#{quoted(geometry.to_json)}), 4326)")).to be >= 500
  end
end
