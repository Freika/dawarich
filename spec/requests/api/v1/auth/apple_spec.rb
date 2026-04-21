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
      expect do
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      end.to change(User, :count).by(1)

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
      expect do
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      end.not_to change(User, :count)

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

  context 'existing user matched by email (potential ATO)' do
    let!(:existing) { create(:user, email: 'apple@example.com') }

    context 'when Apple asserts email_verified == "true"' do
      before do
        allow(verifier_double).to receive(:call).and_return(
          sub: '000777.apple',
          email: 'apple@example.com',
          email_verified: 'true'
        )
      end

      it 'links the OAuth identity to the existing user' do
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
        expect(response).to have_http_status(:ok)
        expect(existing.reload.provider).to eq('apple')
        expect(existing.reload.uid).to eq('000777.apple')
      end
    end

    context 'when Apple does NOT assert email_verified' do
      before do
        allow(verifier_double).to receive(:call).and_return(
          sub: '000777.apple',
          email: 'apple@example.com'
        )
      end

      it 'refuses to merge the OAuth identity and returns 403 email_not_verified' do
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('email_not_verified')
        expect(existing.reload.provider).to be_nil
        expect(existing.reload.uid).to be_nil
      end
    end

    context 'when Apple asserts email_verified == "false"' do
      before do
        allow(verifier_double).to receive(:call).and_return(
          sub: '000777.apple',
          email: 'apple@example.com',
          email_verified: 'false'
        )
      end

      it 'refuses to merge the OAuth identity and returns 403' do
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
        expect(response).to have_http_status(:forbidden)
        expect(existing.reload.provider).to be_nil
      end
    end
  end

  context 'on a self-hosted instance' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(verifier_double).to receive(:call).and_return(
        sub: '000444.apple',
        email: 'selfhost-apple@example.com'
      )
    end

    it 'creates the user in active status (not pending_payment)' do
      expect do
        post '/api/v1/auth/apple', params: { id_token: 'fake_token' }
      end.to change(User, :count).by(1)

      user = User.find_by(uid: '000444.apple')
      expect(user.status).to eq('active')
      expect(user.plan).to eq('pro')
      expect(user.active_until).to be > 900.years.from_now
    end
  end
end
