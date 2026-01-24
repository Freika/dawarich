# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Sessions', type: :request do
  let(:user) { create(:user, password: 'password123') }

  describe 'POST /users/sign_in' do
    context 'when OIDC is not enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      end

      it 'allows email/password login' do
        post user_session_path, params: {
          user: { email: user.email, password: 'password123' }
        }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_nil
      end

      it 'allows login even when ALLOW_EMAIL_PASSWORD_REGISTRATION is false' do
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)

        post user_session_path, params: {
          user: { email: user.email, password: 'password123' }
        }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_nil
      end
    end

    context 'when OIDC is enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is true' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)
        end

        it 'allows email/password login' do
          post user_session_path, params: {
            user: { email: user.email, password: 'password123' }
          }

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to be_nil
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_REGISTRATION is false (OIDC-only mode)' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)
        end

        it 'blocks email/password login' do
          post user_session_path, params: {
            user: { email: user.email, password: 'password123' }
          }

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to include('Email/password login is disabled')
        end

        it 'does not complete the sign in flow' do
          post user_session_path, params: {
            user: { email: user.email, password: 'password123' }
          }

          # The request should be redirected before authentication completes
          expect(response).to redirect_to(root_path)
          # Follow redirect and verify no successful login message
          follow_redirect!
          expect(response.body).not_to include('Signed in successfully')
        end
      end
    end
  end

  describe 'GET /users/sign_in' do
    context 'when OIDC is enabled and ALLOW_EMAIL_PASSWORD_REGISTRATION is false' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)
      end

      it 'renders the login page (to show OIDC buttons)' do
        get new_user_session_path

        expect(response).to have_http_status(:ok)
      end

      it 'does not show email/password form fields' do
        get new_user_session_path

        expect(response.body).not_to include('type="password"')
        expect(response.body).to include('Sign in using your organization')
      end
    end

    context 'when OIDC is not enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      end

      it 'shows email/password form fields' do
        get new_user_session_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('type="password"')
      end
    end
  end
end
