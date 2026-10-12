# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/points anomaly filtering inside a bounding box', type: :request do
  let(:user) { create(:user) }
  let(:now)  { Time.zone.now }

  let!(:normal_point) do
    create(:point,
           user: user,
           timestamp: now.to_i,
           latitude: 52.5,
           longitude: 13.4,
           lonlat: 'POINT(13.4 52.5)',
           anomaly: false)
  end

  let!(:anomaly_point) do
    create(:point,
           user: user,
           timestamp: now.to_i + 60,
           latitude: 52.51,
           longitude: 13.41,
           lonlat: 'POINT(13.41 52.51)',
           anomaly: true)
  end

  let(:bbox_params) do
    'min_longitude=13.0&max_longitude=14.0&min_latitude=52.0&max_latitude=53.0'
  end

  let(:time_params) do
    "start_at=#{(now - 1.hour).to_i}&end_at=#{(now + 1.hour).to_i}"
  end

  def fetch_ids(extra_params = '')
    get "/api/v1/points?api_key=#{user.api_key}&#{time_params}&#{bbox_params}&#{extra_params}"
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).map { |p| p['id'] }
  end

  it 'defaults to non-anomaly points only' do
    expect(fetch_ids).to contain_exactly(normal_point.id)
  end

  it 'returns only anomaly points when anomalies_only=true' do
    expect(fetch_ids('anomalies_only=true')).to contain_exactly(anomaly_point.id)
  end

  it 'returns both normal and anomaly points when include_anomalies=true' do
    expect(fetch_ids('include_anomalies=true'))
      .to contain_exactly(normal_point.id, anomaly_point.id)
  end

  it 'gives anomalies_only precedence when both flags are set' do
    expect(fetch_ids('anomalies_only=true&include_anomalies=true'))
      .to contain_exactly(anomaly_point.id)
  end
end
