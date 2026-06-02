# frozen_string_literal: true

require 'rails_helper'

# The authoritative list of map read endpoints that MUST honour
# mask_privacy_zones=true. Adding a new map endpoint? Add it here and
# implement masking, or this spec stays red.
MASKED_MAP_ENDPOINTS = %w[
  points places visits photos tracks hexagons track_points
].freeze

RSpec.describe 'Privacy zone masking contract', type: :request do
  let(:user) { create(:user) }

  before do
    tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: 1000)
    place = create(:place, user: user, latitude: 52.444, longitude: 13.500)
    create(:tagging, tag: tag, taggable: place)
  end

  it 'enumerates every masked map endpoint (update when adding a map layer)' do
    expect(MASKED_MAP_ENDPOINTS).to contain_exactly(
      'points', 'places', 'visits', 'photos', 'tracks', 'hexagons', 'track_points'
    )
  end

  it 'omits the in-zone point from points#index with the flag' do
    create(:point, user: user, lonlat: 'POINT(13.500 52.444)', timestamp: 1.hour.ago.to_i)
    create(:point, user: user, lonlat: 'POINT(13.700 52.600)', timestamp: 1.hour.ago.to_i)

    get api_v1_points_url(api_key: user.api_key, mask_privacy_zones: 'true', per_page: 100)

    coords = JSON.parse(response.body).map { |p| [p['longitude'].to_f, p['latitude'].to_f] }
    expect(coords).not_to include([13.500, 52.444])
  end

  it 'omits the in-zone place from places#index with the flag' do
    zone_place = user.places.first
    far = create(:place, user: user, latitude: 52.600, longitude: 13.700)

    get '/api/v1/places',
        params: { mask_privacy_zones: 'true' },
        headers: { 'Authorization' => "Bearer #{user.api_key}" }

    ids = JSON.parse(response.body).map { |p| p['id'] }
    expect(ids).to include(far.id)
    expect(ids).not_to include(zone_place.id)
  end
end
