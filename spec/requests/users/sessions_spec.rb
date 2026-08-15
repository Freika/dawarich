# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Sessions', type: :request do
  let(:user) { create(:user, password: 'password123456') }

  describe 'POST /users/sign_in' do
    context 'when OIDC is not enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      end

      it 'allows email/password login' do
        post user_session_path, params: {
          user: { email: user.email, password: 'password123456' }
        }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_nil
      end

      it 'allows login even when ALLOW_EMAIL_PASSWORD_REGISTRATION is false' do
        stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', false)

        post user_session_path, params: {
          user: { email: user.email, password: 'password123456' }
        }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_nil
      end
    end

    context 'when OIDC is enabled' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
      end

      context 'when ALLOW_EMAIL_PASSWORD_LOGIN is true' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', true)
        end

        it 'allows email/password login' do
          post user_session_path, params: {
            user: { email: user.email, password: 'password123456' }
          }

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to be_nil
        end
      end

      context 'when ALLOW_EMAIL_PASSWORD_LOGIN is false (OIDC-only mode)' do
        before do
          stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)
        end

        it 'blocks email/password login' do
          post user_session_path, params: {
            user: { email: user.email, password: 'password123456' }
          }

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to include('Email/password login is disabled')
        end

        it 'does not complete the sign in flow' do
          post user_session_path, params: {
            user: { email: user.email, password: 'password123456' }
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
    context 'when OIDC is enabled and ALLOW_EMAIL_PASSWORD_LOGIN is false' do
      before do
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
        stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)
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
        expect(response.body).to include('value="Log in"')
      end

      it 'renders the French persistent-session label' do
        get new_user_session_path(locale: 'fr')

        expect(response.body).to include('Se souvenir de moi')
        expect(response.body).to include('value="Se connecter"')
      end

      it 'renders an invited user French heading as one complete sentence' do
        family = create(:family, name: 'Famille Test')
        invitation = create(:family_invitation, family:, invited_by: family.creator)

        get new_user_session_path(invitation_token: invitation.token, locale: 'fr')

        expect(response.body).to include('Se connecter pour rejoindre Famille Test !')
        expect(response.body).not_to include('Se connecter pour rejoindre.')
      end
    end
  end
end
