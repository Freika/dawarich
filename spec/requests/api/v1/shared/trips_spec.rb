# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Shared::Trips', type: :request do
  let(:owner) { create(:user) }
  let(:trip)  { create(:trip, user: owner, name: 'Norway 2026') }
  let(:link)  { create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id) }

  it 'returns 404 for missing link' do
    get '/api/v1/shared/00000000-0000-0000-0000-000000000000/trip'
    expect(response).to have_http_status(:not_found)
  end

  it 'returns 401 for phrase-protected link without unlock cookie' do
    link.update!(magic_phrase: 'open-sesame-now')
    get "/api/v1/shared/#{link.id}/trip"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns trip metadata' do
    get "/api/v1/shared/#{link.id}/trip"
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['name']).to eq('Norway 2026')
    expect(body).to have_key('started_at')
    expect(body).to have_key('ended_at')
  end

  it 'omits distance when show_stats is false' do
    link.update!(settings: link.settings.merge('show_stats' => false))
    get "/api/v1/shared/#{link.id}/trip"
    body = JSON.parse(response.body)
    expect(body).not_to have_key('distance')
  end

  it 'returns distance converted to the owner unit when show_stats is on' do
    trip.update!(distance: 5000)
    link.update!(settings: link.settings.merge('show_stats' => true))
    get "/api/v1/shared/#{link.id}/trip"
    body = JSON.parse(response.body)
    unit = owner.safe_settings.distance_unit
    expect(body['distance']).to eq(trip.distance_in_unit(unit).round)
    expect(body['distance_unit']).to eq(unit)
  end

  it 'never leaks owner email or API key' do
    get "/api/v1/shared/#{link.id}/trip"
    expect(response.body).not_to include(owner.email)
    expect(response.body).not_to include(owner.api_key.to_s)
  end
end
