# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Shared::Tiles', type: :request do
  let(:owner) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:trip) do
    create(:trip, user: owner, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 3), path: nil,
                  skip_calculation_enqueue: true)
  end
  let(:link) { create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id) }
  let(:zoom) { 10 }

  def tile_path(shared_link = link)
    n = 2**zoom
    lat = -40 * Math::PI / 180
    x = ((-140.02 + 180) / 360 * n).floor
    y = ((1 - (Math.log(Math.tan(lat) + (1 / Math.cos(lat))) / Math::PI)) / 2 * n).floor
    "/api/v1/shared/#{shared_link.id}/tiles/#{zoom}/#{x}/#{y}.mvt"
  end

  def record_route
    track = create(:track, user: owner, tracker_id: 'phone', start_at: Time.utc(2026, 1, 1, 10),
                           end_at: Time.utc(2026, 1, 1, 10, 10),
                           original_path: 'LINESTRING(-140.02 -40, -140.021 -40, -140.022 -40)')
    [-140.02, -140.021, -140.022].each_with_index do |longitude, index|
      create(:point, user: owner, track:, tracker_id: 'phone', timestamp: Time.utc(2026, 1, 1, 10, index * 5).to_i,
                     lonlat: "POINT(#{longitude} -40)")
    end
  end

  def add_privacy_zone
    home = create(:place, user: owner, latitude: -40.0, longitude: -140.021)
    tag = create(:tag, user: owner, privacy_radius_meters: 1_000)
    create(:tagging, tag:, taggable: home)
  end

  before { record_route }

  it 'serves the shared trip routes publicly for a short time' do
    get tile_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
    expect(response.body.b).to include('trip_routes'.b)
    expect(response.headers['Cache-Control']).to include('public', 'max-age=30')
  end

  it 'returns not found for unknown, expired and non-trip links' do
    get '/api/v1/shared/00000000-0000-0000-0000-000000000000/tiles/10/0/0.mvt'
    expect(response).to have_http_status(:not_found)

    get tile_path(create(:shared_link, :expired, user: owner, resource_type: :trip, resource_id: trip.id))
    expect(response).to have_http_status(:not_found)

    get tile_path(create(:shared_link, :live, user: owner))
    expect(response).to have_http_status(:not_found)
  end

  it 'returns not found when the owner hides the route' do
    link.update!(settings: link.settings.merge('show_route' => false))

    get tile_path

    expect(response).to have_http_status(:not_found)
  end

  it 'requires the unlock cookie for a phrase-protected link and then never caches' do
    link.update!(magic_phrase: 'open-sesame-now')

    get tile_path
    expect(response).to have_http_status(:unauthorized)

    post "/s/#{link.id}/unlock", params: { phrase: 'open-sesame-now' }
    get tile_path

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(response.headers['Vary']).to include('Cookie')
  end

  it 'never serves route geometry inside a privacy zone' do
    add_privacy_zone

    get tile_path

    expect(response).to have_http_status(:no_content)
  end

  it 'changes the ETag when the owner adds a privacy zone' do
    get tile_path
    etag = response.headers['ETag']
    get tile_path, headers: { 'If-None-Match' => etag }
    expect(response).to have_http_status(:not_modified)

    add_privacy_zone
    get tile_path, headers: { 'If-None-Match' => etag }

    expect(response).not_to have_http_status(:not_modified)
  end

  it "keeps a Lite owner's routes before the data window off the shared map" do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    owner.update!(plan: :lite)
    old_start = 2.years.ago.change(hour: 10)
    trip.update_columns(started_at: old_start.beginning_of_day, ended_at: old_start.end_of_day)
    [-140.02, -140.021, -140.022].each_with_index do |longitude, index|
      create(:point, user: owner, track: nil, timestamp: (old_start + (index * 5).minutes).to_i,
                     lonlat: "POINT(#{longitude} -40)")
    end

    get tile_path

    expect(response).to have_http_status(:no_content)
  end

  it 'revalidates the tiles once the owner moves to a plan with a data window' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    owner.update!(plan: :pro)
    get tile_path
    etag = response.headers['ETag']

    owner.update!(plan: :lite)
    get tile_path, headers: { 'If-None-Match' => etag }

    expect(response).not_to have_http_status(:not_modified)
  end

  it 'does not accept exclusion windows' do
    get tile_path, params: { exclude: '1-2' }

    expect(response).to have_http_status(:bad_request)
  end

  it 'serves family links to members without shared caching' do
    member = create(:user)
    family = create(:family, creator: owner)
    create(:family_membership, :owner, family:, user: owner)
    create(:family_membership, family:, user: member)
    family_link = create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                                       settings: { 'audience' => 'family', 'family_id' => family.id,
                                                   'show_route' => true })
    sign_in member

    get tile_path(family_link)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(response.headers['Vary']).to include('Cookie')
  end
end
