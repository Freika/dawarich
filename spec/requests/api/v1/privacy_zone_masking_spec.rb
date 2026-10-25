# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Privacy zone masking on map read endpoints', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:zone_lon) { 13.500 }
  let(:zone_lat) { 52.444 }
  let(:zone_radius) { 500 }
  let(:time_range) { { start_at: 2.days.ago.iso8601, end_at: Time.current.iso8601 } }
  let!(:zone_place) do
    tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: zone_radius)
    place = create(:place, user: user, name: 'Home', latitude: zone_lat, longitude: zone_lon,
                           lonlat: "POINT(#{zone_lon} #{zone_lat})")
    create(:tagging, tag: tag, taggable: place)
    place
  end

  def json
    JSON.parse(response.body)
  end

  def masked(params = {})
    params.merge(mask_privacy_zones: 'true')
  end

  def distance_to_zone(lon, lat)
    Geocoder::Calculations.distance_between([lat.to_f, lon.to_f], [zone_lat, zone_lon], units: :km) * 1000
  end

  def vertices(geometry)
    case geometry['type']
    when 'LineString' then geometry['coordinates']
    when 'MultiLineString' then geometry['coordinates'].flatten(1)
    else []
    end
  end

  describe 'points' do
    before do
      create(:point, user: user, lonlat: "POINT(#{zone_lon} #{zone_lat})", timestamp: 2.hours.ago.to_i)
      create(:point, user: user, lonlat: 'POINT(13.700 52.600)', timestamp: 1.hour.ago.to_i)
    end

    it 'drops in-zone points with the flag and keeps them without it' do
      get '/api/v1/points', params: masked(per_page: 100), headers: headers
      masked_coords = json.map { |p| [p['longitude'].to_f, p['latitude'].to_f] }

      get '/api/v1/points', params: { per_page: 100 }, headers: headers
      plain_coords = json.map { |p| [p['longitude'].to_f, p['latitude'].to_f] }

      expect(masked_coords).to contain_exactly([13.700, 52.600])
      expect(plain_coords).to include([zone_lon, zone_lat])
    end

    it 'does not answer the masked request with the unmasked ETag' do
      get '/api/v1/points', params: { per_page: 100 }, headers: headers
      etag = response.headers['ETag']

      get '/api/v1/points', params: masked(per_page: 100), headers: headers.merge('If-None-Match' => etag)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'track_points' do
    let(:track) { create(:track, user: user, start_at: 3.hours.ago, end_at: 30.minutes.ago) }

    before do
      create(:point, user: user, track: track, lonlat: "POINT(#{zone_lon} #{zone_lat})", timestamp: 2.hours.ago.to_i)
      create(:point, user: user, track: track, lonlat: 'POINT(13.700 52.600)', timestamp: 1.hour.ago.to_i)
    end

    it 'drops in-zone track points only with the flag' do
      get "/api/v1/tracks/#{track.id}/points", params: masked, headers: headers
      masked_count = json.size

      get "/api/v1/tracks/#{track.id}/points", headers: headers

      expect(masked_count).to eq(1)
      expect(json.size).to eq(2)
    end
  end

  describe 'places' do
    let!(:far_place) do
      create(:place, user: user, latitude: 52.600, longitude: 13.700, lonlat: 'POINT(13.700 52.600)')
    end

    it 'hides the in-zone place only with the flag' do
      get '/api/v1/places', params: masked(filter: 'all'), headers: headers
      masked_ids = json.map { |p| p['id'] }

      get '/api/v1/places', params: { filter: 'all' }, headers: headers

      expect(masked_ids).to include(far_place.id)
      expect(masked_ids).not_to include(zone_place.id)
      expect(json.map { |p| p['id'] }).to include(zone_place.id)
    end
  end

  describe 'visits' do
    let!(:place_visit) do
      create(:visit, user: user, place: zone_place, area: nil, started_at: 2.hours.ago, ended_at: 1.hour.ago)
    end
    let!(:area_visit) do
      area = create(:area, user: user, latitude: zone_lat, longitude: zone_lon)
      create(:visit, user: user, area: area, place: nil, started_at: 4.hours.ago, ended_at: 3.hours.ago)
    end
    let!(:far_visit) do
      area = create(:area, user: user, latitude: 52.600, longitude: 13.700)
      create(:visit, user: user, area: area, place: nil, started_at: 6.hours.ago, ended_at: 5.hours.ago)
    end

    it 'drops visits at an in-zone place or area only with the flag' do
      get '/api/v1/visits', params: masked(time_range), headers: headers
      masked_ids = json.map { |v| v['id'] }

      get '/api/v1/visits', params: time_range, headers: headers

      expect(masked_ids).to contain_exactly(far_visit.id)
      expect(json.map { |v| v['id'] }).to include(place_visit.id, area_visit.id, far_visit.id)
    end
  end

  describe 'photos' do
    let(:user) { create(:user, :with_photoprism_integration) }
    let(:photos) do
      [
        { 'id' => 'in', 'latitude' => zone_lat, 'longitude' => zone_lon, 'source' => 'photoprism' },
        { 'id' => 'out', 'latitude' => 52.600, 'longitude' => 13.700, 'source' => 'photoprism' }
      ]
    end

    before do
      search = instance_double(Photos::Search, call: photos, errors: [], all_sources_failed?: false)
      allow(Photos::Search).to receive(:new).and_return(search)
    end

    it 'drops in-zone photos only with the flag, also when served from cache' do
      params = { start_date: 2.days.ago.to_date.to_s, end_date: Date.current.to_s }

      get '/api/v1/photos', params: params, headers: headers
      plain_ids = json.map { |p| p['id'] }

      get '/api/v1/photos', params: masked(params), headers: headers

      expect(plain_ids).to contain_exactly('in', 'out')
      expect(json.map { |p| p['id'] }).to contain_exactly('out')
    end
  end

  describe 'tracks' do
    let!(:track) do
      create(:track, user: user, start_at: 2.hours.ago, end_at: 1.hour.ago,
                     original_path: 'LINESTRING(13.40 52.444, 13.60 52.444)')
    end

    it 'cuts the track index geometry at the zone only with the flag' do
      get '/api/v1/tracks', params: masked(time_range), headers: headers
      masked_geometry = json['features'].first['geometry']

      get '/api/v1/tracks', params: time_range, headers: headers

      expect(masked_geometry['type']).to eq('MultiLineString')
      expect(vertices(masked_geometry).map { |lon, lat| distance_to_zone(lon, lat) }.min).to be >= zone_radius
      expect(json['features'].first['geometry']['type']).to eq('LineString')
    end

    it 'cuts the single track geometry at the zone only with the flag' do
      get "/api/v1/tracks/#{track.id}", params: masked, headers: headers
      masked_geometry = json['features'].first['geometry']

      expect(vertices(masked_geometry).map { |lon, lat| distance_to_zone(lon, lat) }.min).to be >= zone_radius
    end

    it 'cuts segment paths at the zone and drops segments entirely inside it' do
      crossing = create(:track_segment, track:, start_index: 0, end_index: 1,
                                        start_at: 2.hours.ago, end_at: 90.minutes.ago,
                                        path: 'SRID=4326;LINESTRING(13.40 52.444, 13.60 52.444)')
      inside = create(:track_segment, track:, start_index: 1, end_index: 2,
                                      start_at: 90.minutes.ago, end_at: 1.hour.ago,
                                      path: "SRID=4326;LINESTRING(#{zone_lon} #{zone_lat}, 13.5005 52.4441)")

      get "/api/v1/tracks/#{track.id}", params: masked, headers: headers
      segments = json['features'].first['properties']['segments']

      expect(segments.map { |s| s['id'] }).to contain_exactly(crossing.id)
      expect(segments.map { |s| s['id'] }).not_to include(inside.id)
      cut = vertices('type' => 'MultiLineString', 'coordinates' => segments.first['coordinates'])
      expect(cut.map { |lon, lat| distance_to_zone(lon, lat) }.min).to be >= zone_radius
    end

    it 'drops a track that lies entirely inside the zone' do
      inside = create(:track, user: user, start_at: 3.hours.ago, end_at: 2.5.hours.ago,
                              original_path: "LINESTRING(#{zone_lon} #{zone_lat}, 13.5005 52.4441)")

      get '/api/v1/tracks', params: masked(time_range), headers: headers

      expect(json['features'].map { |f| f['properties']['id'] }).not_to include(inside.id)
    end
  end

  describe 'location search' do
    before do
      create(:point, user: user, lonlat: "POINT(#{zone_lon} #{zone_lat})", timestamp: 2.hours.ago.to_i)
      create(:point, user: user, lonlat: 'POINT(13.520 52.444)', timestamp: 1.hour.ago.to_i)
    end

    def visit_coordinates
      json['locations'].flat_map { |l| l['visits'] }.map { |v| v['coordinates'] }
    end

    it 'leaves in-zone points out of the search results only with the flag' do
      params = { lat: zone_lat, lon: zone_lon, radius_override: 2000 }

      get '/api/v1/locations', params: masked(params), headers: headers
      masked_coordinates = visit_coordinates

      get '/api/v1/locations', params: params, headers: headers

      expect(masked_coordinates).not_to include([zone_lat, zone_lon])
      expect(masked_coordinates).to be_present
      expect(visit_coordinates).to include([zone_lat, zone_lon])
    end
  end

  describe 'bounds' do
    before do
      create(:point, user: user, lonlat: "POINT(#{zone_lon} #{zone_lat})", timestamp: 2.hours.ago.to_i)
      create(:point, user: user, lonlat: 'POINT(13.700 52.600)', timestamp: 1.hour.ago.to_i)
      create(:point, user: user, lonlat: 'POINT(13.710 52.610)', timestamp: 50.minutes.ago.to_i)
    end

    it 'ignores in-zone points when fitting the map only with the flag' do
      params = { start_date: 2.days.ago.iso8601, end_date: Time.current.iso8601 }

      get '/api/v1/maps/hexagons/bounds', params: masked(params), headers: headers
      masked_min_lng = json['min_lng']

      get '/api/v1/maps/hexagons/bounds', params: params, headers: headers

      expect(masked_min_lng).to be > 13.6
      expect(json['min_lng']).to be < 13.6
    end
  end

  describe 'shared monthly stats' do
    let(:zone_cell) { H3.to_string(H3.from_geo_coordinates([zone_lat, zone_lon], 8)) }
    let(:far_cell) { H3.to_string(H3.from_geo_coordinates([52.600, 13.700], 8)) }
    let(:june) { Time.utc(2024, 6, 15, 12).to_i }
    let(:stat) do
      create(:stat, :with_sharing_enabled, user: user, year: 2024, month: 6,
                                           h3_hex_ids: [[zone_cell, 3, june, june], [far_cell, 2, june, june]])
    end

    before do
      create(:point, user: user, lonlat: "POINT(#{zone_lon} #{zone_lat})", timestamp: june)
      create(:point, user: user, lonlat: 'POINT(13.700 52.600)', timestamp: june + 60)
      create(:point, user: user, lonlat: 'POINT(13.710 52.610)', timestamp: june + 120)
    end

    it 'drops hexagons touching the zone without needing the flag' do
      get '/api/v1/maps/hexagons', params: { uuid: stat.sharing_uuid }

      centers = json['features'].map do |feature|
        ring = feature['geometry']['coordinates'].first
        [ring.sum { |c| c[1] } / ring.size, ring.sum { |c| c[0] } / ring.size]
      end

      expect(json['features'].size).to eq(1)
      expect(H3.to_string(H3.from_geo_coordinates(centers.first, 8))).to eq(far_cell)
    end

    it 'ignores in-zone points when fitting the shared map without needing the flag' do
      get '/api/v1/maps/hexagons/bounds', params: { uuid: stat.sharing_uuid }

      expect(json['min_lng']).to be > 13.6
    end

    it 'ignores in-zone points in the bounds embedded in the shared page' do
      get shared_stat_url(stat.sharing_uuid)

      bounds = JSON.parse(CGI.unescapeHTML(response.body[/data-public-stat-map-data-bounds-value="([^"]*)"/, 1]))

      expect(bounds['min_lng']).to be > 13.6
    end
  end
end
