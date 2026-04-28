# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users', type: :request do
  describe 'GET /me' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'returns success response' do
      get '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:success)
    end

    it 'returns only the keys and values stated in the serializer' do
      get '/api/v1/users/me', headers: headers

      json = JSON.parse(response.body, symbolize_names: true)

      expect(json.keys).to eq([:user])
      expect(json[:user].keys).to match_array(
        %i[email theme created_at updated_at settings]
      )
      expect(json[:user][:settings].keys).to match_array(
        %i[
          timezone maps fog_of_war_meters meters_between_routes preferred_map_layer
          speed_colored_routes points_rendering_mode minutes_between_routes
          time_threshold_minutes merge_threshold_minutes live_map_enabled
          route_opacity immich_url photoprism_url visits_suggestions_enabled
          speed_color_scale fog_of_war_threshold globe_projection
        ]
      )
    end

    context 'when the user is in pending_payment status' do
      let(:user) do
        u = create(:user, skip_auto_trial: true)
        u.update!(status: :pending_payment)
        u
      end

      it 'returns 402 with payment_required envelope' do
        get '/api/v1/users/me', headers: headers

        expect(response).to have_http_status(:payment_required)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('payment_required')
        expect(body['resume_url']).to be_present
      end
    end
  end

  describe 'POST /api/v1/users/exist' do
    let(:webhook_secret) { 'test_webhook_secret' }
    let(:webhook_headers) { { 'X-Webhook-Secret' => webhook_secret } }

    before do
      stub_const('ENV', ENV.to_h.merge('SUBSCRIPTION_WEBHOOK_SECRET' => webhook_secret))
    end

    context 'with the correct webhook secret' do
      let!(:user_a) { create(:user) }
      let!(:user_b) { create(:user) }

      it 'returns existing and missing arrays for the requested ids' do
        missing_id = User.maximum(:id).to_i + 9_999

        post '/api/v1/users/exist',
             params: { ids: [user_a.id, user_b.id, missing_id] }.to_json,
             headers: webhook_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['existing']).to match_array([user_a.id, user_b.id])
        expect(body['missing']).to eq([missing_id])
      end

      it 'handles non-numeric ids by routing them to missing without raising' do
        post '/api/v1/users/exist',
             params: { ids: [user_a.id, 'notanumber', nil] }.to_json,
             headers: webhook_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['existing']).to eq([user_a.id])
      end

      it 'returns empty arrays when ids is empty' do
        post '/api/v1/users/exist',
             params: { ids: [] }.to_json,
             headers: webhook_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['existing']).to eq([])
        expect(body['missing']).to eq([])
      end

      it 'returns 422 with a clear error when ids is missing entirely' do
        post '/api/v1/users/exist',
             params: {}.to_json,
             headers: webhook_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['error']).to eq('ids is required')
      end
    end

    context 'webhook secret validation' do
      let!(:user_a) { create(:user) }

      it 'returns unauthorized without the X-Webhook-Secret header' do
        post '/api/v1/users/exist',
             params: { ids: [user_a.id] }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized with a wrong webhook secret' do
        post '/api/v1/users/exist',
             params: { ids: [user_a.id] }.to_json,
             headers: { 'X-Webhook-Secret' => 'wrong', 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns service_unavailable when SUBSCRIPTION_WEBHOOK_SECRET is not configured' do
        stub_const('ENV', ENV.to_h.merge('SUBSCRIPTION_WEBHOOK_SECRET' => nil))

        post '/api/v1/users/exist',
             params: { ids: [user_a.id] }.to_json,
             headers: webhook_headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end
end
