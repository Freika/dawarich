# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /metrics', type: :request do
  before do
    allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)
  end

  it 'returns 401 without credentials' do
    get '/metrics'
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['WWW-Authenticate']).to start_with('Basic realm=')
  end

  it 'returns 401 with wrong credentials' do
    get '/metrics', headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('nope', 'wrong') }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns Prometheus text with valid credentials' do
    get '/metrics',
        headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(METRICS_USERNAME, METRICS_PASSWORD) }

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with('text/plain')
    expect(response.body).to include('# HELP', '# TYPE')
    expect(response.body).to include('dawarich_archive_operations_total')
  end

  it 'returns 404 when prometheus exporter is disabled' do
    allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(false)

    get '/metrics',
        headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(METRICS_USERNAME, METRICS_PASSWORD) }

    expect(response).to have_http_status(:not_found)
  end
end
