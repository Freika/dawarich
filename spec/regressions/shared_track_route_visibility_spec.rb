# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared track route visibility', type: :request do
  let(:owner) { create(:user) }
  let(:track) { create(:track, user: owner, start_at: Time.utc(2026, 5, 1), end_at: Time.utc(2026, 5, 1, 1)) }
  let!(:point) { create(:point, user: owner, track: track, timestamp: track.start_at.to_i + 60) }

  it 'omits the map and route coordinates when the route is disabled, retaining enabled statistics' do
    link = create(:shared_link, user: owner, resource_type: :track, resource_id: track.id,
                                settings: { 'show_route' => false, 'show_stats' => true })

    get "/s/#{link.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('shared-trip-map')
    expect(response.body).to include('Distance')

    get "/api/v1/shared/#{link.id}/points"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  [true, nil].each do |value|
    it "retains the map and coordinates when show_route is #{value.inspect}" do
      settings = value.nil? ? {} : { 'show_route' => value }
      link = create(:shared_link, user: owner, resource_type: :track, resource_id: track.id, settings: settings)

      get "/s/#{link.id}"
      expect(response.body).to include('shared-trip-map')
      get "/api/v1/shared/#{link.id}/points"
      expect(response.parsed_body.length).to eq(1)
    end
  end
end
