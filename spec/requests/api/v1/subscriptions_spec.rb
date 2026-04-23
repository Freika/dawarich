# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Subscriptions', type: :request do
  let(:user) { create(:user, :inactive, plan: :lite, subscription_source: :none) }
  let(:jwt_secret) { 'test_secret' }
  let(:webhook_secret) { 'test_webhook_secret' }
  let(:webhook_headers) { { 'X-Webhook-Secret' => webhook_secret } }

  before do
    Rails.cache.clear
    stub_const('ENV', ENV.to_h.merge(
                        'JWT_SECRET_KEY' => jwt_secret,
                        'SUBSCRIPTION_WEBHOOK_SECRET' => webhook_secret
                      ))
  end

  # `event_id` is required by the subscription-callback contract — we supply
  # a random default so individual tests don't need to set it unless they
  # are specifically exercising the idempotency / missing-event_id paths.
  def build_token(payload)
    defaults = { exp: 30.minutes.from_now.to_i, event_id: "paddle:#{SecureRandom.uuid}" }
    JWT.encode(defaults.merge(payload), jwt_secret, 'HS256')
  end

  describe 'POST /api/v1/subscriptions/callback' do
    context 'webhook secret validation' do
      it 'returns unauthorized without the X-Webhook-Secret header' do
        post '/api/v1/subscriptions/callback', params: { token: 'any' }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['message']).to eq('Invalid webhook secret')
      end

      it 'returns unauthorized with a wrong webhook secret' do
        post '/api/v1/subscriptions/callback',
             params: { token: 'any' },
             headers: { 'X-Webhook-Secret' => 'wrong' }

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns service_unavailable when SUBSCRIPTION_WEBHOOK_SECRET is not configured' do
        stub_const('ENV', ENV.to_h.merge('SUBSCRIPTION_WEBHOOK_SECRET' => nil))

        post '/api/v1/subscriptions/callback',
             params: { token: 'any' },
             headers: webhook_headers

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'with a valid token and the correct webhook secret' do
      let(:active_until) { 30.days.from_now.change(usec: 0) }
      let(:token) do
        build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: active_until.iso8601,
          subscription_source: 'paddle',
          event_id: SecureRandom.uuid
        )
      end

      it 'updates the user and returns 200' do
        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['message']).to eq('Subscription updated successfully')

        user.reload
        expect(user.status).to eq('active')
        expect(user.plan).to eq('pro')
        expect(user.subscription_source).to eq('paddle')
        expect(user.active_until.to_i).to eq(active_until.to_i)
      end
    end

    context 'idempotency via event_id' do
      let(:event_id) { SecureRandom.uuid }

      it 'is idempotent: duplicate events do not re-apply changes' do
        first_token = build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: event_id
        )

        post '/api/v1/subscriptions/callback', params: { token: first_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.plan).to eq('pro')
        expect(user.status).to eq('active')

        # Replay with same event_id but different desired state. It must NOT be applied.
        replay_token = build_token(
          user_id: user.id,
          plan: 'lite',
          status: 'inactive',
          active_until: 1.year.ago.iso8601,
          subscription_source: 'none',
          event_id: event_id
        )

        post '/api/v1/subscriptions/callback', params: { token: replay_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['message']).to eq('Stale event')

        user.reload
        expect(user.plan).to eq('pro')
        expect(user.status).to eq('active')
      end
    end

    context 'when event_id is missing' do
      it 'returns 422 and does not mutate the user' do
        user.update!(status: :inactive, plan: :lite)

        token = JWT.encode(
          {
            user_id: user.id,
            status: 'active',
            active_until: 30.days.from_now.iso8601,
            plan: 'pro',
            exp: 30.minutes.from_now.to_i
          },
          jwt_secret,
          'HS256'
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['message']).to eq('Missing event_id')
        user.reload
        expect(user.status).to eq('inactive')
        expect(user.plan).to eq('lite')
      end
    end

    context 'subscription_source handling' do
      it 'updates subscription_source when present in the token' do
        token = build_token(
          user_id: user.id,
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'apple_iap'
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.subscription_source).to eq('apple_iap')
      end

      it 'leaves subscription_source unchanged when absent from the token' do
        user.update!(subscription_source: :paddle)

        token = build_token(
          user_id: user.id,
          status: 'active',
          active_until: 30.days.from_now.iso8601
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.subscription_source).to eq('paddle')
      end
    end

    context 'plan handling' do
      it 'updates plan when a known value is provided' do
        token = build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.plan).to eq('pro')
      end

      it 'ignores an unknown plan value but still applies other attributes' do
        user.update!(plan: :lite)

        token = build_token(
          user_id: user.id,
          plan: 'enterprise',
          status: 'active',
          active_until: 30.days.from_now.iso8601
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.plan).to eq('lite')
        expect(user.status).to eq('active')
      end

      it 'leaves plan unchanged when the field is absent' do
        user.update_column(:plan, User.plans[:pro])

        token = build_token(
          user_id: user.id,
          status: 'active',
          active_until: 30.days.from_now.iso8601
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.plan).to eq('pro')
      end
    end

    context 'malformed JWT' do
      it 'returns unauthorized for a garbage token' do
        post '/api/v1/subscriptions/callback',
             params: { token: 'obviously-not-a-jwt' },
             headers: webhook_headers

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['message']).to eq('Failed to verify subscription update.')
      end
    end
  end
end
