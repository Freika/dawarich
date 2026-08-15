# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/visits with bbox selection respects date range', type: :request do
  let(:user) { create(:user) }
  let(:auth_headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  let(:place_inside) { create(:place, latitude: 50.0, longitude: 14.0) }

  let!(:visit_in_range) do
    create(:visit, user: user, place: place_inside,
                   started_at: 1.day.ago, ended_at: 1.day.ago + 1.hour)
  end

  let!(:visit_out_of_range) do
    create(:visit, user: user, place: place_inside,
                   started_at: 5.years.ago, ended_at: 5.years.ago + 1.hour)
  end

  it 'returns only visits inside the date range when bbox selection is active' do
    get '/api/v1/visits', params: {
      selection: 'true',
      sw_lat: '49.0', sw_lng: '13.0',
      ne_lat: '51.0', ne_lng: '15.0',
      start_at: 2.days.ago.iso8601,
      end_at: Time.zone.now.iso8601
    }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).pluck('id')
    expect(ids).to include(visit_in_range.id)
    expect(ids).not_to include(visit_out_of_range.id)
  end

  it 'returns all visits inside the bbox when no date range is given' do
    get '/api/v1/visits', params: {
      selection: 'true',
      sw_lat: '49.0', sw_lng: '13.0',
      ne_lat: '51.0', ne_lng: '15.0'
    }, headers: auth_headers

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).pluck('id')
    expect(ids).to include(visit_in_range.id, visit_out_of_range.id)
  end
end
