# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/google', type: :request do
  let(:verifier_double) { instance_double(Auth::VerifyGoogleToken) }

  before do
    allow(Auth::VerifyGoogleToken).to receive(:new).and_return(verifier_double)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  context 'first-time Google user' do
    before do
      allow(verifier_double).to receive(:call).and_return(
        sub: 'google-uid-123',
        email: 'google@example.com',
        email_verified: true
      )
    end

    it 'creates a new user in pending_payment with provider google and uid' do
      expect do
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
      end.to change(User, :count).by(1)

      user = User.find_by(email: 'google@example.com')
      expect(user.status).to eq('pending_payment')
      expect(user.subscription_source).to eq('none')
      expect(user.provider).to eq('google')
      expect(user.uid).to eq('google-uid-123')
    end

    it 'returns 201 with api_key' do
      post '/api/v1/auth/google', params: { id_token: 'fake_token' }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to include('api_key', 'user_id', 'email')
    end
  end

  context 'returning Google user' do
    let!(:existing) { create(:user, email: 'google@example.com', provider: 'google', uid: 'google-uid-123') }

    before do
      allow(verifier_double).to receive(:call).and_return(
        sub: 'google-uid-123',
        email: 'google@example.com'
      )
    end

    it 'returns existing user without creating a new one' do
      expect do
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['user_id']).to eq(existing.id)
    end
  end

  context 'invalid token' do
    before do
      allow(verifier_double).to receive(:call).and_raise(Auth::VerifyGoogleToken::InvalidToken, 'bad token')
    end

    it 'returns 401' do
      post '/api/v1/auth/google', params: { id_token: 'invalid' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'existing user matched by email (potential ATO)' do
    let!(:existing) { create(:user, email: 'google@example.com') }

    context 'when Google asserts email_verified == true (default: verification required)' do
      before do
        allow(verifier_double).to receive(:call).and_return(
          sub: 'google-uid-777',
          email: 'google@example.com',
          email_verified: true
        )
      end

      it 'does NOT merge the identity; returns 202 and enqueues a verification email' do
        expect do
          post '/api/v1/auth/google', params: { id_token: 'fake_token' }
        end.to have_enqueued_job(Users::MailerSendingJob).with(
          existing.id, 'oauth_account_link', hash_including(:link_url, provider_label: 'Google')
        )

        expect(response).to have_http_status(:accepted)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('verification_sent')
        expect(existing.reload.provider).to be_nil
        expect(existing.reload.uid).to be_nil
      end
    end

    # PR-A: the legacy silent-link path (Flipper-gated in PR-B) is removed.
    # All email-collision flows go through the email-link verification path
    # tested above.

    context 'when Google does NOT assert email_verified' do
      before do
        allow(verifier_double).to receive(:call).and_return(
          sub: 'google-uid-777',
          email: 'google@example.com'
        )
      end

      it 'refuses to merge the OAuth identity and returns 403 email_not_verified' do
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('email_not_verified')
        expect(existing.reload.provider).to be_nil
        expect(existing.reload.uid).to be_nil
      end
    end

    context 'when Google asserts email_verified == false' do
      before do
        allow(verifier_double).to receive(:call).and_return(
          sub: 'google-uid-777',
          email: 'google@example.com',
          email_verified: false
        )
      end

      it 'refuses to merge the OAuth identity and returns 403' do
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
        expect(response).to have_http_status(:forbidden)
        expect(existing.reload.provider).to be_nil
      end
    end
  end

  context 'on a self-hosted instance' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(verifier_double).to receive(:call).and_return(
        sub: 'google-selfhost-uid',
        email: 'selfhost-google@example.com'
      )
    end

    it 'creates the user in active status (not pending_payment)' do
      expect do
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
      end.to change(User, :count).by(1)

      user = User.find_by(uid: 'google-selfhost-uid')
      expect(user.status).to eq('active')
      expect(user.plan).to eq('pro')
      expect(user.active_until).to be > 900.years.from_now
    end
  end
end
