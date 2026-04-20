require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/apple', type: :request do
  let(:verifier_double) { instance_double(Auth::VerifyAppleToken) }

  before do
    allow(Auth::VerifyAppleToken).to receive(:new).and_return(verifier_double)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  context 'first-time Apple user' do
    before do
      allow(verifier_double).to receive(:call).and_return(
        sub: '000123.apple',
        email: 'apple@example.com',
        email_verified: 'true'
      )
    end

    it 'creates a new user in pending_payment with subscription_source none' do
      expect {
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      }.to change(User, :count).by(1)

      user = User.find_by(email: 'apple@example.com')
      expect(user.status).to eq('pending_payment')
      expect(user.subscription_source).to eq('none')
      expect(user.provider).to eq('apple')
      expect(user.uid).to eq('000123.apple')
    end

    it 'returns 201 with api_key' do
      post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)).to include('api_key', 'user_id', 'email')
    end
  end

  context 'returning Apple user' do
    let!(:existing) { create(:user, email: 'apple@example.com', provider: 'apple', uid: '000123.apple') }

    before do
      allow(verifier_double).to receive(:call).and_return(
        sub: '000123.apple',
        email: 'apple@example.com'
      )
    end

    it 'returns existing user without creating a new one' do
      expect {
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['user_id']).to eq(existing.id)
    end
  end

  context 'invalid token' do
    before do
      allow(verifier_double).to receive(:call).and_raise(Auth::VerifyAppleToken::InvalidToken, 'bad token')
    end

    it 'returns 401' do
      post '/api/v1/auth/apple', params: { id_token: 'invalid' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'relay email (Apple private relay)' do
    before do
      allow(verifier_double).to receive(:call).and_return(
        sub: '000999.apple',
        email: 'abc@privaterelay.appleid.com'
      )
    end

    it 'treats the relay address as the canonical email' do
      post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      user = User.find_by(uid: '000999.apple')
      expect(user.email).to eq('abc@privaterelay.appleid.com')
    end
  end
end
