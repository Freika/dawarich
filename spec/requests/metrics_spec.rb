# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '/metrics', type: :request do
  describe 'GET /metrics' do
    # audit M-3: with empty METRICS_USERNAME / METRICS_PASSWORD env vars
    # the prior defaults exposed the endpoint with prometheus/prometheus.
    # The fail-closed change refuses to serve until both vars are set.
    context 'when METRICS_USERNAME / METRICS_PASSWORD are not configured' do
      before do
        stub_const('METRICS_USERNAME', nil)
        stub_const('METRICS_PASSWORD', nil)
      end

      it 'returns 503 Service Unavailable' do
        get metrics_path
        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when credentials are configured but missing in the request' do
      before do
        stub_const('METRICS_USERNAME', 'metric_user')
        stub_const('METRICS_PASSWORD', 'metric_pass')
      end

      it 'returns 401 Unauthorized' do
        get metrics_path
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
