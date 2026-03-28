# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Subscriptions', type: :request do
  let(:user) { create(:user, :inactive) }
  let(:jwt_secret) { ENV['JWT_SECRET_KEY'] }

  let(:webhook_secret) { 'test_webhook_secret' }
  let(:webhook_headers) { { 'X-Webhook-Secret' => webhook_secret } }

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'JWT_SECRET_KEY' => 'test_secret',
                        'SUBSCRIPTION_WEBHOOK_SECRET' => webhook_secret
                      ))
  end

  context 'when Dawarich is not self-hosted' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    describe 'POST /api/v1/subscriptions/callback' do
      context 'without webhook secret header' do
        it 'returns unauthorized' do
          post '/api/v1/subscriptions/callback', params: { token: 'any' }

          expect(response).to have_http_status(:unauthorized)
          expect(JSON.parse(response.body)['message']).to eq('Invalid webhook secret')
        end
      end

      context 'with wrong webhook secret' do
        it 'returns unauthorized' do
          post '/api/v1/subscriptions/callback',
               params: { token: 'any' },
               headers: { 'X-Webhook-Secret' => 'wrong' }

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when SUBSCRIPTION_WEBHOOK_SECRET is not configured' do
        before do
          stub_const('ENV', ENV.to_h.merge(
                              'JWT_SECRET_KEY' => 'test_secret',
                              'SUBSCRIPTION_WEBHOOK_SECRET' => nil
                            ))
        end

        it 'returns service unavailable' do
          post '/api/v1/subscriptions/callback',
               params: { token: 'any' },
               headers: webhook_headers

          expect(response).to have_http_status(:service_unavailable)
        end
      end

      context 'with valid webhook secret' do
        context 'with valid token' do
          let(:token) do
            JWT.encode(
              { user_id: user.id, status: 'active', active_until: 1.year.from_now },
              'test_secret',
              'HS256'
            )
          end

          it 'updates user status and returns success message' do
            decoded_data = { user_id: user.id, status: 'active', active_until: 1.year.from_now.to_s }
            mock_decoder = instance_double(Subscription::DecodeJwtToken, call: decoded_data)
            allow(Subscription::DecodeJwtToken).to receive(:new).with(token).and_return(mock_decoder)

            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(user.reload.status).to eq('active')
            expect(user.active_until).to be_within(1.day).of(1.year.from_now)
            expect(response).to have_http_status(:ok)
            expect(JSON.parse(response.body)['message']).to eq('Subscription updated successfully')
          end
        end

        context 'with valid token containing plan' do
          let(:token) do
            JWT.encode(
              { user_id: user.id, status: 'active', active_until: 1.year.from_now, plan: 'pro' },
              'test_secret',
              'HS256'
            )
          end

          it 'updates user plan from JWT payload' do
            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(user.reload.plan).to eq('pro')
            expect(user.reload.status).to eq('active')
            expect(response).to have_http_status(:ok)
          end
        end

        context 'with valid token containing lite plan' do
          let(:token) do
            JWT.encode(
              { user_id: user.id, status: 'active', active_until: 1.year.from_now, plan: 'lite' },
              'test_secret',
              'HS256'
            )
          end

          it 'sets user plan to lite' do
            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(user.reload.plan).to eq('lite')
            expect(response).to have_http_status(:ok)
          end
        end

        context 'with valid token containing invalid plan' do
          let(:token) do
            JWT.encode(
              { user_id: user.id, status: 'active', active_until: 1.year.from_now, plan: 'enterprise' },
              'test_secret',
              'HS256'
            )
          end

          it 'returns unprocessable_content error' do
            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(response).to have_http_status(:unprocessable_content)
            expect(JSON.parse(response.body)['message']).to include('Invalid plan')
          end
        end

        context 'with valid token without plan field' do
          let(:token) do
            JWT.encode(
              { user_id: user.id, status: 'active', active_until: 1.year.from_now },
              'test_secret',
              'HS256'
            )
          end

          it 'does not change user plan' do
            user.update_column(:plan, User.plans[:pro])
            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(user.reload.plan).to eq('pro')
            expect(response).to have_http_status(:ok)
          end
        end

        context 'with token for different user' do
          let(:other_user) { create(:user) }
          let(:token) do
            JWT.encode(
              { user_id: other_user.id, status: 'active', active_until: 1.year.from_now },
              jwt_secret,
              'HS256'
            )
          end

          it 'updates provided user' do
            decoded_data = { user_id: other_user.id, status: 'active', active_until: 1.year.from_now.to_s }
            mock_decoder = instance_double(Subscription::DecodeJwtToken, call: decoded_data)
            allow(Subscription::DecodeJwtToken).to receive(:new).with(token).and_return(mock_decoder)

            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(user.reload.status).not_to eq('active')
            expect(other_user.reload.status).to eq('active')
            expect(response).to have_http_status(:ok)
          end
        end

        context 'with invalid token' do
          it 'returns unauthorized error with decode error message' do
            allow(Subscription::DecodeJwtToken).to receive(:new).with('invalid')
                                                                .and_raise(JWT::DecodeError.new('Invalid token'))

            post '/api/v1/subscriptions/callback',
                 params: { token: 'invalid' },
                 headers: webhook_headers

            expect(response).to have_http_status(:unauthorized)
            expect(JSON.parse(response.body)['message']).to eq('Failed to verify subscription update.')
          end
        end

        context 'with malformed token data' do
          let(:token) do
            JWT.encode({ user_id: 'invalid', status: nil }, jwt_secret, 'HS256')
          end

          it 'returns unprocessable_content error with invalid data message' do
            allow(Subscription::DecodeJwtToken).to receive(:new).with(token)
                                                                .and_raise(ArgumentError.new('Invalid token data'))

            post '/api/v1/subscriptions/callback',
                 params: { token: token },
                 headers: webhook_headers

            expect(response).to have_http_status(:unprocessable_content)
            expect(JSON.parse(response.body)['message']).to eq('Invalid subscription data received.')
          end
        end
      end
    end
  end

  context 'when Dawarich is self-hosted' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    end

    describe 'POST /api/v1/subscriptions/callback' do
      it 'is blocked for self-hosted instances' do
        post '/api/v1/subscriptions/callback',
             params: { token: 'invalid' },
             headers: webhook_headers

        expect([401, 302, 303, 422, 503]).to include(response.status)
      end
    end
  end
end
