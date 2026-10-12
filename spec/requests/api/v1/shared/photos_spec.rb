# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Shared::Photos', type: :request do
  let(:owner) { create(:user) }
  let(:trip)  { create(:trip, user: owner) }

  context 'when show_photos is false' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => false })
    end

    it 'returns empty array on index regardless of integration' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'returns 404 for thumbnail requests' do
      get "/api/v1/shared/#{link.id}/photos/foo/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when show_photos is true but owner has no integration' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end

    it 'returns empty array' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  context 'when show_photos is true and the trip has photos' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end
    let(:found_photos) do
      [{ id: 'asset-1', source: 'immich', latitude: 52.0, longitude: 13.0,
         localDateTime: '2026-04-02T14:30:00', capturedAt: '2026-04-02T13:30:00Z' }]
    end

    before do
      allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
    end

    it 'includes latitude and longitude so the map can place markers' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      photo = JSON.parse(response.body).first
      expect(photo).to include('id' => 'asset-1', 'latitude' => 52.0, 'longitude' => 13.0)
      expect(photo['thumbnail_url']).to be_present
    end

    it 'includes taken_at so replay can reveal photos by timestamp' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).first['taken_at']).to eq('2026-04-02T13:30:00Z')
    end

    it 'serves thumbnails for photos belonging to the trip' do
      upstream = instance_double(HTTParty::Response, success?: true, body: 'jpeg-bytes')
      allow(Photos::Thumbnail).to receive(:new).with(owner, 'immich', 'asset-1').and_return(
        instance_double(Photos::Thumbnail, call: upstream)
      )

      get "/api/v1/shared/#{link.id}/photos/asset-1/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('jpeg-bytes')
    end

    it 'returns 404 for photo ids outside the trip without contacting the integration' do
      expect(Photos::Thumbnail).not_to receive(:new)

      get "/api/v1/shared/#{link.id}/photos/foreign-asset/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when a photo falls inside a privacy zone' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end
    let(:found_photos) do
      [{ id: 'public-1', source: 'immich', latitude: 60.0, longitude: 10.0 },
       { id: 'private-1', source: 'immich', latitude: 52.0, longitude: 13.0 }]
    end

    before do
      allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
      home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
      tag = create(:tag, user: owner, privacy_radius_meters: 500)
      create(:tagging, tag: tag, taggable: home)
    end

    it 'excludes the masked photo from the index' do
      get "/api/v1/shared/#{link.id}/photos"
      ids = JSON.parse(response.body).map { |p| p['id'] }
      expect(ids).to eq(['public-1'])
    end

    it 'returns 404 for a masked photo thumbnail without contacting the integration' do
      expect(Photos::Thumbnail).not_to receive(:new)
      get "/api/v1/shared/#{link.id}/photos/private-1/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'for a track share with photos' do
    let(:track) do
      create(:track, user: owner, start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 14))
    end
    let(:link) do
      create(:shared_link, user: owner, resource_type: :track, resource_id: track.id,
                           settings: { 'show_photos' => true })
    end
    let(:found_photos) { [{ id: 'asset-1', source: 'immich', latitude: 52.0, longitude: 13.0 }] }

    before do
      allow(Photos::Search).to receive(:new).and_return(instance_double(Photos::Search, call: found_photos))
    end

    it 'returns geotagged photos within the track window' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).first).to include('id' => 'asset-1', 'latitude' => 52.0)
    end

    it 'searches photos within the track start_at..end_at range' do
      expect(Photos::Search).to receive(:new).with(
        owner, start_date: track.start_at.iso8601, end_date: track.end_at.iso8601
      ).and_return(instance_double(Photos::Search, call: found_photos))

      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
    end
  end
end
