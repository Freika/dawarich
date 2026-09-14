# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points::Positions', type: :request do
  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(1_000), end_at: Time.zone.at(1_120),
                   original_path: 'LINESTRING(0 0, 0.02 0)')
  end
  let!(:point) { create(:point, user:, track:, timestamp: 1_000, longitude: 0, latitude: 0) }
  let!(:other_point) { create(:point, user:, track:, timestamp: 1_120, longitude: 0.02, latitude: 0) }
  let(:params) do
    {
      point: { latitude: 0.01, longitude: 0.01, revision: point.lock_version },
      track_revision: track.lock_version,
      history_scope: { start_at: Time.zone.at(900).iso8601, end_at: Time.zone.at(1_200).iso8601 }
    }
  end

  it 'returns the canonical point and recalculated track' do
    patch "/api/v1/points/#{point.id}/position?api_key=#{user.api_key}", params: params

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('point', 'revision')).to eq(1)
    expect(response.parsed_body.dig('track', 'properties', 'revision')).to eq(1)
    expect(response.parsed_body.dig('track', 'geometry', 'coordinates')).to eq([[0.01, 0.01], [0.02, 0.0]])
  end

  it 'accepts the minute-precision ISO-8601 scope emitted by the map' do
    params[:history_scope] = {
      start_at: Time.zone.at(900).strftime('%Y-%m-%dT%H:%M%:z'),
      end_at: Time.zone.at(1_200).strftime('%Y-%m-%dT%H:%M%:z')
    }

    patch "/api/v1/points/#{point.id}/position?api_key=#{user.api_key}", params: params

    expect(response).to have_http_status(:ok)
  end

  it 'returns 409 with canonical state for a stale edit' do
    params[:point][:revision] += 1

    patch "/api/v1/points/#{point.id}/position?api_key=#{user.api_key}", params: params

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('stale_edit')
    expect(response.parsed_body.dig('point', 'longitude')).to eq('0.0')
  end

  it 'rejects invalid coordinates without changing the point' do
    params[:point][:latitude] = 'NaN'

    patch "/api/v1/points/#{point.id}/position?api_key=#{user.api_key}", params: params

    expect(response).to have_http_status(:unprocessable_entity)
    expect(point.reload.lat).to eq(0.0)
  end
end
