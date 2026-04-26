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

    context 'event ordering via event_timestamp_ms' do
      it 'skips an event whose event_timestamp_ms is older than the last seen for that user' do
        newer_ts = 2_000_000_000_000
        older_ts = 1_000_000_000_000

        newer_token = build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: SecureRandom.uuid,
          event_timestamp_ms: newer_ts
        )

        post '/api/v1/subscriptions/callback', params: { token: newer_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.plan).to eq('pro')
        expect(user.status).to eq('active')

        # Older event arrives later (out-of-order delivery). Must be ignored.
        older_token = build_token(
          user_id: user.id,
          plan: 'lite',
          status: 'inactive',
          active_until: 1.year.ago.iso8601,
          subscription_source: 'none',
          event_id: SecureRandom.uuid,
          event_timestamp_ms: older_ts
        )

        post '/api/v1/subscriptions/callback', params: { token: older_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['message']).to eq('Stale event')

        user.reload
        expect(user.plan).to eq('pro')
        expect(user.status).to eq('active')
      end

      it 'still processes events when event_timestamp_ms is missing (back-compat)' do
        token = build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: SecureRandom.uuid
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.plan).to eq('pro')
      end

      it 'advances the last-seen watermark on each successful event' do
        first_ts = 1_500_000_000_000
        second_ts = 1_600_000_000_000
        third_ts = 1_550_000_000_000

        first_token = build_token(
          user_id: user.id,
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          plan: 'pro',
          event_id: SecureRandom.uuid,
          event_timestamp_ms: first_ts
        )
        post '/api/v1/subscriptions/callback', params: { token: first_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)

        second_token = build_token(
          user_id: user.id,
          status: 'active',
          active_until: 60.days.from_now.iso8601,
          plan: 'pro',
          subscription_source: 'apple_iap',
          event_id: SecureRandom.uuid,
          event_timestamp_ms: second_ts
        )
        post '/api/v1/subscriptions/callback', params: { token: second_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.subscription_source).to eq('apple_iap')

        # Third event has a timestamp older than the watermark (now=second_ts).
        # Should be rejected even though it's newer than first_ts.
        third_token = build_token(
          user_id: user.id,
          status: 'inactive',
          active_until: 1.year.ago.iso8601,
          plan: 'lite',
          subscription_source: 'none',
          event_id: SecureRandom.uuid,
          event_timestamp_ms: third_ts
        )
        post '/api/v1/subscriptions/callback', params: { token: third_token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['message']).to eq('Stale event')

        user.reload
        expect(user.plan).to eq('pro')
        expect(user.subscription_source).to eq('apple_iap')
      end
    end

    context 'plan handling - unknown plan contract' do
      it 'applies status/active_until/subscription_source even when plan is unknown' do
        user.update!(status: :inactive, plan: :lite, subscription_source: :none)
        active_until = 30.days.from_now.change(usec: 0)

        token = build_token(
          user_id: user.id,
          plan: 'enterprise',
          status: 'active',
          active_until: active_until.iso8601,
          subscription_source: 'paddle'
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)

        user.reload
        expect(user.status).to eq('active')
        expect(user.active_until.to_i).to eq(active_until.to_i)
        expect(user.subscription_source).to eq('paddle')
      end

      it 'leaves plan unchanged when decoded plan is unknown' do
        user.update_column(:plan, User.plans[:pro])

        token = build_token(
          user_id: user.id,
          plan: 'enterprise',
          status: 'active',
          active_until: 30.days.from_now.iso8601
        )

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.plan).to eq('pro')
      end
    end
  end
end
