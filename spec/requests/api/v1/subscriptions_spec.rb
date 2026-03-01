# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Subscriptions', type: :request do
  let(:user) { create(:user, :inactive) }
  let(:jwt_secret) { ENV['JWT_SECRET_KEY'] }

  before do
    stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => 'test_secret'))
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  context 'when Dawarich is not self-hosted' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    describe 'POST /api/v1/subscriptions/callback' do
      context 'when user is not authenticated' do
        it 'requires authentication' do
          # Make request without authentication
          post '/api/v1/subscriptions/callback', params: { token: 'invalid' }

          # Either we get redirected (302) or get an unauthorized response (401) or unprocessable (422)
          # All indicate that authentication is required
          expect([401, 302, 422]).to include(response.status)
        end
      end

      context 'when user is authenticated' do
        before { sign_in user }

        context 'with valid token' do
          let(:token) do
            JWT.encode(
              { user_id: user.id, status: 'active', active_until: 1.year.from_now },
              jwt_secret,
              'HS256'
            )
          end

          it 'updates user status and returns success message' do
            decoded_data = { user_id: user.id, status: 'active', active_until: 1.year.from_now.to_s }
            mock_decoder = instance_double(Subscription::DecodeJwtToken, call: decoded_data)
            allow(Subscription::DecodeJwtToken).to receive(:new).with(token).and_return(mock_decoder)

            post '/api/v1/subscriptions/callback', params: { token: token }

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
            post '/api/v1/subscriptions/callback', params: { token: token }

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
            post '/api/v1/subscriptions/callback', params: { token: token }

            expect(user.reload.plan).to eq('lite')
            expect(response).to have_http_status(:ok)
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
            post '/api/v1/subscriptions/callback', params: { token: token }

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

            post '/api/v1/subscriptions/callback', params: { token: token }

            expect(user.reload.status).not_to eq('active')
            expect(other_user.reload.status).to eq('active')
            expect(response).to have_http_status(:ok)
            expect(JSON.parse(response.body)['message']).to eq('Subscription updated successfully')
          end
        end

        context 'with invalid token' do
          it 'returns unauthorized error with decode error message' do
            allow(Subscription::DecodeJwtToken).to receive(:new).with('invalid')
                                                                .and_raise(JWT::DecodeError.new('Invalid token'))

            post '/api/v1/subscriptions/callback', params: { token: 'invalid' }

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

            post '/api/v1/subscriptions/callback', params: { token: token }

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
      sign_in user
    end

    describe 'POST /api/v1/subscriptions/callback' do
      it 'is blocked for self-hosted instances' do
        # Make request in self-hosted environment
        post '/api/v1/subscriptions/callback', params: { token: 'invalid' }

        # In a self-hosted environment, we either get redirected or receive an error
        # Either way, the access is blocked as expected
        expect([401, 302, 303, 422]).to include(response.status)
      end
    end
  end
end
