# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Traccar rejected point responses', type: :request do
  let(:user) { create(:user) }
  let(:form_payload) do
    { id: 'synthetic-device', timestamp: '1785920400', lat: '48.2082', lon: '16.3738' }
  end

  it 'acknowledges a repeated upload without duplicating the point or counter' do
    2.times do
      post "/api/v1/traccar/points?api_key=#{user.api_key}", params: form_payload
      expect(response).to have_http_status(:ok)
    end

    expect(user.points.count).to eq(1)
    expect(user.reload.points_count).to eq(1)
  end

  it 'stores millisecond timestamps as seconds' do
    post "/api/v1/traccar/points?api_key=#{user.api_key}",
         params: form_payload.merge(timestamp: '1785920400000')

    expect(response).to have_http_status(:ok)
    expect(user.points.sole.timestamp).to eq(1_785_920_400)
  end

  it 'does not acknowledge a location deliberately filtered by intake' do
    expect do
      post "/api/v1/traccar/points?api_key=#{user.api_key}", params: form_payload.merge(lat: '0', lon: '0')
    end.not_to change(Point, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects an empty payload' do
    post "/api/v1/traccar/points?api_key=#{user.api_key}", params: {}, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.points).to be_empty
  end

  it 'stores a Traccar form-protocol point' do
    payload = {
      id: 'synthetic-device',
      timestamp: '1785920400',
      lat: '48.2082',
      lon: '16.3738',
      accuracy: '6.0',
      speed: '9.72',
      batt: '80',
      charge: 'false'
    }

    expect do
      post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload
    end.to change(Point, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it 'returns a non-success response when the payload cannot create a point' do
    payload = {
      id: 'synthetic-device',
      timestamp: '2026-08-05T09:00:00Z',
      lat: 'invalid',
      lon: '16.3738'
    }

    expect do
      post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload
    end.not_to change(Point, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to include('error')
  end
end
