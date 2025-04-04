# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::Subscriptions', type: :request do
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

    describe 'GET /settings/subscriptions' do
      context 'when user is not authenticated' do
        it 'redirects to login page' do
          get settings_subscriptions_path

          expect(response).to redirect_to(new_user_session_path)
        end
      end

      context 'when user is authenticated' do
        before { sign_in user }

        it 'returns successful response' do
          get settings_subscriptions_path

          expect(response).to be_successful
        end
      end
    end

    describe 'GET /settings/subscriptions/callback' do
      context 'when user is not authenticated' do
        it 'redirects to login page' do
          get subscription_callback_settings_subscriptions_path(token: 'invalid')

          expect(response).to redirect_to(new_user_session_path)
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

          it 'updates user status and redirects with success message' do
            get subscription_callback_settings_subscriptions_path(token: token)

            expect(user.reload.status).to eq('active')
            expect(user.active_until).to be_within(1.day).of(1.year.from_now)
            expect(response).to redirect_to(settings_subscriptions_path)
            expect(flash[:notice]).to eq('Your subscription has been updated successfully!')
          end
        end

        context 'with token for different user' do
          let(:other_user) { create(:user) }
          let(:token) do
            JWT.encode(
              { user_id: other_user.id, status: 'active' },
              jwt_secret,
              'HS256'
            )
          end

          it 'does not update status and redirects with error' do
            get subscription_callback_settings_subscriptions_path(token: token)

            expect(user.reload.status).not_to eq('active')
            expect(response).to redirect_to(settings_subscriptions_path)
            expect(flash[:alert]).to eq('Invalid subscription update request.')
          end
        end

        context 'with invalid token' do
          it 'redirects with decode error message' do
            get subscription_callback_settings_subscriptions_path(token: 'invalid')

            expect(response).to redirect_to(settings_subscriptions_path)
            expect(flash[:alert]).to eq('Failed to verify subscription update.')
          end
        end

        context 'with malformed token data' do
          let(:token) do
            JWT.encode({ user_id: 'invalid', status: nil }, jwt_secret, 'HS256')
          end

          it 'redirects with invalid data message' do
            get subscription_callback_settings_subscriptions_path(token: token)

            expect(response).to redirect_to(settings_subscriptions_path)
            expect(flash[:alert]).to eq('Invalid subscription update request.')
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

    describe 'GET /settings/subscriptions' do
      context 'when user is not authenticated' do
        it 'redirects to root path' do
          get settings_subscriptions_path

          expect(response).to redirect_to(root_path)
        end
      end
    end

    describe 'GET /settings/subscriptions/callback' do
      context 'when user is not authenticated' do
        it 'redirects to root path' do
          get subscription_callback_settings_subscriptions_path(token: 'invalid')

          expect(response).to redirect_to(root_path)
        end
      end
    end
  end
end
