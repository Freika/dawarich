# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscription::EncodeJwtToken do
  let(:payload) { { user_id: 123, email: 'test@example.com', action: 'create_user' } }
  let(:secret_key) { 'secret_key' }
  let(:service) { described_class.new(payload, secret_key) }

  describe '#call' do
    it 'encodes JWT with correct algorithm' do
      expect(JWT).to receive(:encode)
        .with(payload, secret_key, 'HS256')
        .and_return('encoded.jwt.token')

      result = service.call
      expect(result).to eq('encoded.jwt.token')
    end

    it 'returns encoded JWT token' do
      token = service.call

      decoded_payload = JWT.decode(token, secret_key, 'HS256').first

      expect(decoded_payload['user_id']).to eq(123)
      expect(decoded_payload['email']).to eq('test@example.com')
      expect(decoded_payload['action']).to eq('create_user')
    end
  end
end
