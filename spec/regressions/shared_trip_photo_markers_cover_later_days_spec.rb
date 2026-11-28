# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared trip photo markers cover later days', type: :request do
  let(:owner) do
    create(:user, settings: { 'immich_url' => 'http://localhost:64995', 'immich_api_key' => 'synthetic-key' })
  end
  let(:trip) do
    create(:trip, user: owner, started_at: Time.utc(2026, 4, 1), ended_at: Time.utc(2026, 4, 4, 23, 59, 59),
                  path: 'LINESTRING(-140 -40, -137 -37)')
  end
  let(:link) do
    create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                         settings: { 'show_photos' => true })
  end
  let(:days) { %w[2026-04-01 2026-04-02 2026-04-03 2026-04-04] }
  let(:assets) do
    [50, 50, 10, 10].each_with_index.flat_map do |count, day|
      Array.new(count) do |index|
        captured_at = Time.utc(2026, 4, day + 1, 12, index).iso8601
        {
          id: "synthetic-day-#{day + 1}-#{index}", type: 'IMAGE',
          fileCreatedAt: captured_at, localDateTime: captured_at,
          exifInfo: { latitude: -40.0 + day, longitude: -140.0 + day }
        }
      end
    end
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    stub_request(:post, 'http://localhost:64995/api/search/metadata').to_return do |request|
      items = JSON.parse(request.body)['page'] == 1 ? assets : []
      { status: 200, body: { assets: { items: items } }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
  end

  it 'keeps later trip days represented after the first two days contain 100 photos' do
    get '/api/v1/photos', params: { api_key: owner.api_key,
                                   start_date: trip.started_at.iso8601, end_date: trip.ended_at.iso8601 }
    expect(response).to have_http_status(:ok)
    owner_photos = JSON.parse(response.body)
    expect(owner_photos.size).to eq(120)
    expect(owner_photos.map { |photo| photo.fetch('capturedAt')[0, 10] }.uniq).to match_array(days)

    get "/api/v1/shared/#{link.id}/photos"
    expect(response).to have_http_status(:ok)
    shared_photos = JSON.parse(response.body)
    expect(shared_photos.map { |photo| photo.fetch('taken_at')[0, 10] }.uniq).to match_array(days)
  end
end
