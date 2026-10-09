# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OIDC auto-login', type: :request do
  let(:user) { create(:user) }
  let(:auth_request_path) { '/users/auth/openid_connect' }

  before(:all) do
    # OMNIAUTH_PROVIDERS is empty in the test environment, so the OIDC request
    # route the auto-login form posts to does not exist yet.
    Rails.application.routes.append do
      devise_scope :user do
        post 'users/auth/openid_connect', to: 'users/omniauth_callbacks#passthru',
                                          as: :user_openid_connect_omniauth_authorize
      end
    end
    Rails.application.reload_routes!
  end

  after(:all) do
    Rails.application.reload_routes!
  end

  def auto_login_form?
    response.body.include?('data-controller="oidc-auto-login"')
  end

  context 'when OIDC auto-login is enabled' do
    before do
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
      stub_const('OIDC_AUTO_LOGIN', true)
    end

    describe 'GET /users/sign_in' do
      it 'renders a form that posts to the OIDC provider' do
        get new_user_session_path

        expect(response).to have_http_status(:ok)
        expect(auto_login_form?).to be(true)
        expect(response.body).to include(%(action="#{auth_request_path}"))
        expect(response.body).to include('method="post"')
      end

      it 'shows the regular sign-in page on the next visit after an attempt' do
        get new_user_session_path
        get new_user_session_path

        expect(auto_login_form?).to be(false)
      end

      it 'tries again on the visit after the regular sign-in page was shown' do
        get new_user_session_path
        get new_user_session_path
        get new_user_session_path

        expect(auto_login_form?).to be(true)
      end

      it 'shows the regular sign-in page with ?auto_login=false' do
        get new_user_session_path(auto_login: false)

        expect(response).to have_http_status(:ok)
        expect(auto_login_form?).to be(false)
      end

      it 'shows the regular sign-in page for family invitations' do
        family = create(:family)
        invitation = create(:family_invitation, family:, invited_by: family.creator)

        get new_user_session_path(invitation_token: invitation.token)

        expect(auto_login_form?).to be(false)
      end

      it 'does not use up the automatic attempt on a prefetch' do
        get new_user_session_path, headers: { 'Sec-Purpose' => 'prefetch' }
        get new_user_session_path

        expect(auto_login_form?).to be(true)
      end

      it 'keeps the regular sign-in page after an attempt when prefetched in between' do
        get new_user_session_path
        get new_user_session_path, headers: { 'Sec-Purpose' => 'prefetch' }
        get new_user_session_path

        expect(auto_login_form?).to be(false)
      end
    end

    describe 'GET /' do
      it 'sends signed-out visitors to the sign-in page' do
        get root_path

        expect(response).to redirect_to(new_user_session_path)
      end

      it 'passes ?auto_login=false on to the sign-in page' do
        get root_path(auto_login: false)

        expect(response).to redirect_to(new_user_session_path(auto_login: false))
      end

      it 'keeps alerts for the sign-in page' do
        stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)

        post user_session_path, params: { user: { email: user.email, password: 'password123456' } }
        follow_redirect!
        follow_redirect!

        expect(response.body).to include('Email/password login is disabled')
      end
    end

    describe 'DELETE /users/sign_out' do
      it 'lands on the sign-in page with auto-login disabled' do
        sign_in user

        delete destroy_user_session_path

        expect(response).to redirect_to(new_user_session_path(auto_login: false))
      end
    end
  end

  context 'when OIDC auto-login is disabled' do
    before do
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
      stub_const('OIDC_AUTO_LOGIN', false)
    end

    it 'shows the regular sign-in page' do
      get new_user_session_path

      expect(auto_login_form?).to be(false)
    end

    it 'keeps the landing page for signed-out visitors' do
      get root_path

      expect(response).to have_http_status(:success)
    end

    it 'redirects to the root path after sign-out' do
      sign_in user

      delete destroy_user_session_path

      expect(response).to redirect_to(root_path)
    end
  end

  context 'when OIDC is not configured' do
    before do
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      stub_const('OIDC_AUTO_LOGIN', true)
    end

    it 'ignores OIDC_AUTO_LOGIN' do
      get new_user_session_path

      expect(auto_login_form?).to be(false)
    end
  end
end
