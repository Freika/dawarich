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

      it 'returns a generic body when SUBSCRIPTION_WEBHOOK_SECRET is not configured (no detail leak)' do
        stub_const('ENV', ENV.to_h.merge('SUBSCRIPTION_WEBHOOK_SECRET' => nil))

        post '/api/v1/subscriptions/callback',
             params: { token: 'any' },
             headers: webhook_headers

        body = JSON.parse(response.body)
        expect(body['message']).to eq('Configuration error')
        expect(body['message']).not_to include('Webhook')
        expect(body['message']).not_to include('secret')
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

      it 'logs a structured subscription_callback_applied event after a successful update' do
        captured = []
        allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
          payload = block ? block.call : args.first
          if payload.is_a?(String) && payload.start_with?('{') &&
             payload.include?('subscription_callback_applied')
            captured << payload
          end
          original.call(*args, &block)
        end

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)

        expect(captured).not_to be_empty, 'Expected a JSON-encoded subscription_callback_applied log line'
        json = JSON.parse(captured.first)
        expect(json['event']).to eq('subscription_callback_applied')
        expect(json['user_id']).to eq(user.id)
        expect(json['status']).to eq('active')
        expect(json['plan']).to eq('pro')
        expect(json['source']).to eq('paddle')
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

    context 'race condition: dedup uses atomic Rails.cache.write(unless_exist:) and a transactional user lock' do
      let(:event_id) { SecureRandom.uuid }
      let(:token) do
        build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: event_id
        )
      end

      it 'uses Rails.cache.write(unless_exist: true) for the processed-events guard (atomic, not exist?+write)' do
        unless_exist_calls = []
        allow(Rails.cache).to receive(:write).and_wrap_original do |original, *args, **opts|
          unless_exist_calls << args.first if opts[:unless_exist]
          original.call(*args, **opts)
        end

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers

        expect(unless_exist_calls).to(
          include(a_string_starting_with('manager_callback:processed:')),
          'Subscription callback dedup MUST claim the event_id key with ' \
          'Rails.cache.write(..., unless_exist: true). The non-atomic exist?+write ' \
          'pattern is a TOCTOU bug that lets two concurrent webhooks both apply.'
        )
      end

      it 'returns Stale event when the atomic claim returns false (lost the race)' do
        call_count = 0
        allow(Rails.cache).to receive(:write).and_wrap_original do |original, *args, **opts|
          if opts[:unless_exist] && args.first.to_s.start_with?('manager_callback:processed:')
            call_count += 1
            call_count == 1 ? original.call(*args, **opts) : false
          else
            original.call(*args, **opts)
          end
        end

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.plan).to eq('pro')
        expect(user.status).to eq('active')

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

      it 'wraps the apply path in a User.transaction so the watermark + update are atomic' do
        expect(User).to receive(:transaction).and_call_original

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).to have_http_status(:ok)
        expect(user.reload.plan).to eq('pro')
      end
    end

    context 'when user.update! raises mid-transaction' do
      let(:event_id) { SecureRandom.uuid }
      let(:event_timestamp_ms) { 1_700_000_000_000 }
      let(:token) do
        build_token(
          user_id: user.id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: event_id,
          event_timestamp_ms: event_timestamp_ms
        )
      end

      before do
        # Simulate validation failure inside the transaction. The cache write
        # for the dedup key has already happened (claim_event!) by the time
        # update! runs, so a rollback alone leaves an orphan dedup key behind.
        allow(User).to receive(:find_by).and_call_original
        allow(User).to receive(:find_by).with(id: user.id).and_return(user)
        allow(user).to receive(:lock!).and_return(user)
        allow(user).to receive(:update!).and_raise(
          ActiveRecord::RecordInvalid.new(user)
        )
      end

      it 'releases the dedup key so Manager retries are not silently dropped' do
        # Rails maps ActiveRecord::RecordInvalid to 422 by default. Whichever
        # status the bubbled exception manifests as, the cache key MUST be
        # released so the Manager's 7-day retry window can recover.
        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).not_to have_http_status(:ok)

        expect(
          Rails.cache.exist?("manager_callback:processed:#{event_id}")
        ).to eq(false)
      end

      it 'does not advance the last-seen watermark' do
        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        expect(response).not_to have_http_status(:ok)

        watermark = Rails.cache.read("manager_callback:last_seen_ms:#{user.id}").to_i
        expect(watermark).to eq(0)
      end
    end

    context 'when the decoded user_id does not match any user on this Dawarich' do
      let(:event_id) { SecureRandom.uuid }
      let(:missing_user_id) { 9_999_999 }
      let(:token) do
        build_token(
          user_id: missing_user_id,
          plan: 'pro',
          status: 'active',
          active_until: 30.days.from_now.iso8601,
          subscription_source: 'paddle',
          event_id: event_id
        )
      end

      it 'returns 404 with an explicit unknown_dawarich_user_id error code' do
        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers

        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('unknown_dawarich_user_id')
        expect(body['user_id']).to eq(missing_user_id)
      end

      it 'logs a structured subscription_callback_unknown_user event' do
        captured = []
        allow(Rails.logger).to receive(:info).and_wrap_original do |original, *args, &block|
          payload = block ? block.call : args.first
          captured << payload if payload.is_a?(String) && payload.include?('subscription_callback_unknown_user')
          original.call(*args, &block)
        end

        post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers

        expect(captured).not_to be_empty
        json = JSON.parse(captured.first)
        expect(json['event']).to eq('subscription_callback_unknown_user')
        expect(json['user_id']).to eq(missing_user_id)
        expect(json['event_id']).to eq(event_id)
      end

      it 'does not raise inside the controller' do
        expect do
          post '/api/v1/subscriptions/callback', params: { token: token }, headers: webhook_headers
        end.not_to raise_error
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
