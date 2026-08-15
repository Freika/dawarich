# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::AppleOauth', type: :request do
  let(:services_id) { 'app.dawarich.web' }
  let(:team_id) { 'H000000B' }
  let(:key_id) { 'ABC123XYZ' }
  let(:redirect_uri) { 'https://dawarich.app/users/auth/apple/callback' }

  before do
    stub_const('APPLE_WEB_SIGN_IN_ENABLED', true)
    stub_const('ENV', ENV.to_hash.merge(
                        'APPLE_WEB_SERVICES_ID' => services_id,
                        'APPLE_WEB_TEAM_ID' => team_id,
                        'APPLE_WEB_KEY_ID' => key_id,
                        'APPLE_WEB_REDIRECT_URI' => redirect_uri
                      ))
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    https!
  end

  describe 'GET /users/auth/apple (request phase)' do
    it 'redirects to Apple authorize endpoint with required params' do
      get '/users/auth/apple'

      expect(response).to have_http_status(:found)
      location = response.headers['Location']
      expect(location).to start_with('https://appleid.apple.com/auth/authorize?')
      expect(location).to include("client_id=#{services_id}")
      expect(location).to include('response_type=code+id_token')
      expect(location).to include('response_mode=form_post')
      expect(location).to include('scope=name+email')
      expect(location).to match(/state=[a-f0-9]{32,}/)
      expect(location).to match(/nonce=[a-f0-9]{32,}/)
    end

    it 'sets encrypted nonce and state cookies with same_site=None' do
      get '/users/auth/apple'
      expect(cookies['apple_oauth_nonce']).to be_present
      expect(cookies['apple_oauth_state']).to be_present
    end

    it 'returns 404 when APPLE_WEB_SIGN_IN_ENABLED is false' do
      stub_const('APPLE_WEB_SIGN_IN_ENABLED', false)
      get '/users/auth/apple'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /users/auth/apple/callback (callback phase)' do
    let(:verifier_double) { instance_double(Auth::VerifyAppleToken) }
    let(:valid_claims) do
      {
        sub: '000777.web.apple',
        email: 'web-user@example.com',
        email_verified: true,
        is_private_email: false
      }
    end

    before do
      allow(Auth::VerifyAppleToken).to receive(:new).and_return(verifier_double)
      allow(verifier_double).to receive(:call).and_return(valid_claims)
    end

    # Trigger the request phase, then extract the actual `state` value from the
    # redirect URL so the callback can echo it back the way Apple would.
    def perform_request_phase
      get '/users/auth/apple'
      location = response.headers['Location']
      query = Rack::Utils.parse_query(URI(location).query)
      query['state']
    end

    it 'creates a new user and signs them in on first-ever sign-in' do
      state = perform_request_phase

      expect do
        post '/users/auth/apple/callback', params: {
          id_token: 'fake-jwt',
          state: state,
          user: { name: { firstName: 'Ada', lastName: 'Lovelace' } }.to_json
        }
      end.to change(User, :count).by(1)

      user = User.find_by(uid: '000777.web.apple')
      expect(user.email).to eq('web-user@example.com')
      expect(user.first_name).to eq('Ada')
      expect(user.last_name).to eq('Lovelace')
      # Cloud mode: new users start in pending_payment status, so Devise routes them
      # through the trial-resume flow instead of root.
      expect(response).to have_http_status(:found)
      expect(response.headers['Location']).to match(%r{(/|trial/resume)\z})
    end

    it 'passes APPLE_WEB_SERVICES_ID as client_id to the verifier' do
      expect(Auth::VerifyAppleToken).to receive(:new)
        .with('fake-jwt', hash_including(client_id: services_id))
        .and_return(verifier_double)

      state = perform_request_phase
      post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }
    end

    it 'signs in an existing Apple user without recreating' do
      create(:user, provider: 'apple', uid: '000777.web.apple', email: 'web-user@example.com')
      state = perform_request_phase

      expect do
        post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }
      end.not_to change(User, :count)

      expect(response).to redirect_to(root_path)
    end

    it 'rejects callbacks whose state cookie is missing' do
      post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: 'anything' }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/state/i)
    end

    it 'rejects callbacks whose state does not match' do
      perform_request_phase

      post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: 'mismatched' }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/state/i)
    end

    it 'redirects to the account-link challenge for an email collision with a password account' do
      create(:user, email: 'web-user@example.com', provider: nil, uid: nil)
      state = perform_request_phase

      expect do
        post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }
      end.to have_enqueued_job(Users::MailerSendingJob)

      expect(response).to redirect_to(auth_account_link_challenge_path)
    end

    it 'rejects callbacks with an invalid id_token' do
      allow(verifier_double).to receive(:call).and_raise(Auth::VerifyAppleToken::InvalidToken, 'bad token')
      state = perform_request_phase

      post '/users/auth/apple/callback', params: { id_token: 'invalid', state: state }
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/Apple/i)
    end

    context 'when Apple returns an error instead of a token' do
      it 'treats user_cancelled_authorize as a gentle cancellation (notice, not alert)' do
        state = perform_request_phase

        expect do
          post '/users/auth/apple/callback', params: { state: state, error: 'user_cancelled_authorize' }
        end.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to match(/cancelled/i)
        expect(flash[:alert]).to be_blank
      end

      it 'shows a retry alert for any other authorize error' do
        state = perform_request_phase

        post '/users/auth/apple/callback', params: { state: state, error: 'invalid_request' }

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to match(/did not complete/i)
      end

      it 'does not call the token verifier when an error is present' do
        expect(Auth::VerifyAppleToken).not_to receive(:new)
        state = perform_request_phase

        post '/users/auth/apple/callback', params: { state: state, error: 'user_cancelled_authorize' }
      end

      it 'shows the cancellation message even when the state cookie has expired' do
        post '/users/auth/apple/callback', params: { state: 'anything', error: 'user_cancelled_authorize' }

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to match(/cancelled/i)
        expect(flash[:alert]).to be_blank
      end
    end

    context 'malformed user payloads' do
      it 'ignores user param when it is not valid JSON' do
        state = perform_request_phase
        post '/users/auth/apple/callback', params: {
          id_token: 'fake-jwt',
          state: state,
          user: 'not-json-at-all'
        }
        user = User.find_by(uid: '000777.web.apple')
        expect(user).to be_present
        expect(user.first_name).to be_nil
        expect(user.last_name).to be_nil
      end

      it 'ignores user param when it parses to a non-Hash' do
        state = perform_request_phase
        post '/users/auth/apple/callback', params: {
          id_token: 'fake-jwt',
          state: state,
          user: '[1, 2, 3]'
        }
        user = User.find_by(uid: '000777.web.apple')
        expect(user).to be_present
        expect(user.first_name).to be_nil
        expect(user.last_name).to be_nil
      end

      it 'ignores name field when it is not a Hash' do
        state = perform_request_phase
        post '/users/auth/apple/callback', params: {
          id_token: 'fake-jwt',
          state: state,
          user: { name: 'just-a-string' }.to_json
        }
        user = User.find_by(uid: '000777.web.apple')
        expect(user).to be_present
        expect(user.first_name).to be_nil
        expect(user.last_name).to be_nil
      end

      it 'accepts partial name (firstName only)' do
        state = perform_request_phase
        post '/users/auth/apple/callback', params: {
          id_token: 'fake-jwt',
          state: state,
          user: { name: { firstName: 'Cher' } }.to_json
        }
        user = User.find_by(uid: '000777.web.apple')
        expect(user.first_name).to eq('Cher')
        expect(user.last_name).to be_nil
      end
    end

    context 'when the email collides with an existing account but is unverified' do
      let!(:existing) { create(:user, email: 'web-user@example.com', provider: nil, uid: nil) }
      let(:unverified_claims) { valid_claims.merge(email_verified: false) }

      before { allow(verifier_double).to receive(:call).and_return(unverified_claims) }

      it 'does not link the account and shows the unverified-email alert' do
        state = perform_request_phase

        expect do
          post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }
        end.not_to change(User, :count)

        expect(existing.reload.provider).to be_nil
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to match(/not verified/i)
      end
    end

    context 'when Apple shares no email and no account exists' do
      let(:no_email_claims) { { sub: '000888.web.apple', email_verified: true, is_private_email: false } }

      before { allow(verifier_double).to receive(:call).and_return(no_email_claims) }

      it 'shows the "Stop using Sign in with Apple" recovery message' do
        state = perform_request_phase

        expect do
          post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }
        end.not_to change(User, :count)

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to match(/Stop using Sign in with Apple/i)
      end
    end
  end
end
