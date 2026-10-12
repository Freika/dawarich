# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::MobileHandoffSecret do
  describe '.call' do
    context 'when AUTH_JWT_SECRET_KEY is set' do
      it 'returns the env value' do
        stub_const('ENV', ENV.to_h.merge('AUTH_JWT_SECRET_KEY' => 'env-auth-secret'))
        expect(described_class.call).to eq('env-auth-secret')
      end
    end

    context 'when AUTH_JWT_SECRET_KEY is unset (self-hosted default)' do
      it 'falls back to Rails.application.secret_key_base' do
        env_without_key = ENV.to_h.tap { |h| h.delete('AUTH_JWT_SECRET_KEY') }
        stub_const('ENV', env_without_key)

        expect(described_class.call).to eq(Rails.application.secret_key_base)
      end
    end

    context 'when AUTH_JWT_SECRET_KEY is an empty string' do
      it 'falls back to Rails.application.secret_key_base (treats blank as unset)' do
        stub_const('ENV', ENV.to_h.merge('AUTH_JWT_SECRET_KEY' => ''))
        expect(described_class.call).to eq(Rails.application.secret_key_base)
      end
    end

    it 'always returns a String so JWT.encode never raises on a nil HMAC key' do
      env_without_key = ENV.to_h.tap { |h| h.delete('AUTH_JWT_SECRET_KEY') }
      stub_const('ENV', env_without_key)

      expect(described_class.call).to be_a(String)
      payload = { api_key: 'abc', exp: 5.minutes.from_now.to_i }
      expect { Subscription::EncodeJwtToken.new(payload, described_class.call).call }.not_to raise_error
    end
  end
end
