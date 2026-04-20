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
      expect {
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
      }.to change(User, :count).by(1)

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
      expect {
        post '/api/v1/auth/google', params: { id_token: 'fake_token' }
      }.not_to change(User, :count)

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
end
