# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public trip photo galleries beyond the map marker limit', type: :request do
  let(:owner) { create(:user) }
  let(:trip) do
    create(:trip, user: owner, started_at: Time.utc(2026, 7, 1), ended_at: Time.utc(2026, 7, 3))
  end
  let(:link) do
    create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                         settings: { 'show_photos' => true })
  end
  let(:photos) do
    100.times.map do |index|
      {
        id: "early-#{index}", source: 'immich', latitude: 52.0, longitude: 13.0,
        capturedAt: '2026-07-01T12:00:00Z'
      }
    end + [
      {
        id: 'later-photo', source: 'immich', latitude: 53.0, longitude: 14.0,
        capturedAt: '2026-07-02T12:00:00Z'
      }
    ]
  end

  before do
    Rails.cache.clear
    allow(Photos::Search).to receive(:cached).and_return(photos)
  end

  it 'groups photos from later days after the first hundred map markers' do
    grouped = SharedLinks::TripPhotos.new(link, timezone: 'Etc/UTC').call

    expect(grouped.fetch(Date.new(2026, 7, 2)).map { _1[:id] }).to include('later-photo')
  end

  it 'authorizes thumbnails after the first hundred map markers' do
    upstream = instance_double(HTTParty::Response, success?: true, body: 'jpeg-bytes')
    allow(Photos::Thumbnail).to receive(:new).with(owner, 'immich', 'later-photo').and_return(
      instance_double(Photos::Thumbnail, call: upstream)
    )

    get "/api/v1/shared/#{link.id}/photos/later-photo/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('jpeg-bytes')
  end

  it 'keeps the public map response capped at one hundred markers' do
    get "/api/v1/shared/#{link.id}/photos"

    expect(JSON.parse(response.body).size).to eq(100)
  end

  it 'does not reuse the old capped thumbnail authorization cache after an upgrade' do
    cache = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(cache)
    old_key = "shared_link/#{link.id}/photo_ids/#{Digest::MD5.hexdigest([].to_s)}"
    cache.write(old_key, ['immich:early-0'], expires_in: 10.minutes)
    upstream = instance_double(HTTParty::Response, success?: true, body: 'jpeg-bytes')
    allow(Photos::Thumbnail).to receive(:new).with(owner, 'immich', 'later-photo').and_return(
      instance_double(Photos::Thumbnail, call: upstream)
    )

    get "/api/v1/shared/#{link.id}/photos/later-photo/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:ok)
  end

  it 'renders deferred galleries for later days even when the map is hidden' do
    link.update!(settings: link.settings.merge('show_route' => false, 'show_days' => true))

    get "/s/#{link.id}"

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css('[data-controller="shared-trip-map"]')).to be_empty
    expect(document.css('template img').size).to eq(101)
    expect(document.css('[data-lazy-gallery-target="content"] img')).to be_empty
    expect(document.css('details[data-controller="lazy-gallery"]').size).to eq(2)
  end

  it 'still excludes private photos beyond the marker limit from galleries and thumbnails' do
    allow(Users::PrivacyZones).to receive(:new).with(owner).and_return(
      instance_double(Users::PrivacyZones, call: [{ lat: 53.0, lon: 14.0, radius: 100 }])
    )

    grouped = SharedLinks::TripPhotos.new(link, timezone: 'Etc/UTC').call
    expect(grouped.values.flatten.map { _1[:id] }).not_to include('later-photo')
    expect(Photos::Thumbnail).not_to receive(:new)

    get "/api/v1/shared/#{link.id}/photos/later-photo/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:not_found)
  end

  it 'does not authorize photos beyond the marker cap for shares without a gallery' do
    track = create(:track, user: owner, start_at: trip.started_at, end_at: trip.ended_at)
    track_link = create(
      :shared_link,
      user: owner,
      resource_type: :track,
      resource_id: track.id,
      settings: { 'show_photos' => true }
    )

    expect(Photos::Thumbnail).not_to receive(:new)

    get "/api/v1/shared/#{track_link.id}/photos/later-photo/thumbnail", params: { source: 'immich' }

    expect(response).to have_http_status(:not_found)
  end
end
