# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Tiles::Trips', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:trip) do
    create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 3), path: nil,
                  skip_calculation_enqueue: true)
  end
  let(:zoom) { 10 }

  def tile_path(owner_trip = trip, longitude: -140.02)
    n = 2**zoom
    lat = -40 * Math::PI / 180
    x = ((longitude + 180) / 360 * n).floor
    y = ((1 - (Math.log(Math.tan(lat) + (1 / Math.cos(lat))) / Math::PI)) / 2 * n).floor
    "/api/v1/tiles/trips/#{owner_trip.id}/#{zoom}/#{x}/#{y}.mvt"
  end

  def record_route(owner = user)
    track = create(:track, user: owner, tracker_id: 'phone', start_at: Time.utc(2026, 1, 1, 10),
                           end_at: Time.utc(2026, 1, 1, 10, 30),
                           original_path: 'LINESTRING(-140 -40, -140.01 -40, -140.02 -40)')
    [-140.0, -140.01, -140.02].each_with_index do |longitude, index|
      create(:point, user: owner, track:, tracker_id: 'phone', timestamp: Time.utc(2026, 1, 1, 10, index * 15).to_i,
                     lonlat: "POINT(#{longitude} -40)")
    end
  end

  def auth
    { 'Authorization' => "Bearer #{user.api_key}" }
  end

  it 'serves the trip routes as a vector tile with day properties' do
    record_route

    get tile_path, headers: auth

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
    expect(response.body.b).to include('trip_routes'.b, 'day'.b, '2026-01-01'.b)
  end

  it 'returns no content for a tile without routes' do
    record_route

    get tile_path(longitude: 10.0), headers: auth

    expect(response).to have_http_status(:no_content)
  end

  it "does not serve another user's trip" do
    other_trip = create(:trip, user: create(:user), skip_calculation_enqueue: true)

    get tile_path(other_trip), headers: auth

    expect(response).to have_http_status(:not_found)
  end

  it 'requires authentication' do
    get tile_path

    expect(response).to have_http_status(:unauthorized)
  end

  it 'revalidates with an ETag that changes when points in the trip change' do
    record_route
    get tile_path, headers: auth
    etag = response.headers['ETag']

    get tile_path, headers: auth.merge('If-None-Match' => etag)
    expect(response).to have_http_status(:not_modified)

    create(:point, user:, track: nil, timestamp: Time.utc(2026, 1, 2, 9).to_i, lonlat: 'POINT(-140.03 -40)')
    get tile_path, headers: auth.merge('If-None-Match' => etag)

    expect(response).to have_http_status(:ok)
  end

  it 'rejects a malformed exclusion list without caching the error' do
    get tile_path, params: { exclude: '20-10' }, headers: auth

    expect(response).to have_http_status(:bad_request)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'accepts flight windows to exclude' do
    record_route

    get tile_path, params: { exclude: "#{Time.utc(2026, 1, 1, 9).to_i}-#{Time.utc(2026, 1, 1, 9, 30).to_i}" },
                   headers: auth

    expect(response).to have_http_status(:ok)
  end

  it 'does not scan the trip for recording devices once they are cached' do
    record_route
    Trip.find(trip.id).multiple_recording_devices?

    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get tile_path, headers: auth }

    expect(response).to have_http_status(:ok)
    expect(statements.grep(/session_number/)).to be_empty
  end
end
