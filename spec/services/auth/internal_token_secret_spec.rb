# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::InternalTokenSecret do
  describe '.call' do
    context 'when JWT_SECRET_KEY is set' do
      it 'returns the env value' do
        stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => 'env-secret-from-cloud'))
        expect(described_class.call).to eq('env-secret-from-cloud')
      end
    end

    context 'when JWT_SECRET_KEY is unset (self-hosted default)' do
      it 'falls back to Rails.application.secret_key_base' do
        env_without_jwt = ENV.to_h.tap { |h| h.delete('JWT_SECRET_KEY') }
        stub_const('ENV', env_without_jwt)

        expect(described_class.call).to eq(Rails.application.secret_key_base)
      end
    end

    context 'when JWT_SECRET_KEY is set to an empty string' do
      it 'falls back to Rails.application.secret_key_base (treats blank as unset)' do
        stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => ''))
        expect(described_class.call).to eq(Rails.application.secret_key_base)
      end
    end

    it 'allows internal tokens to round-trip when JWT_SECRET_KEY is unset' do
      env_without_jwt = ENV.to_h.tap { |h| h.delete('JWT_SECRET_KEY') }
      stub_const('ENV', env_without_jwt)

      user = create(:user)

      otp = Auth::IssueOtpChallengeToken.new(user).call
      expect(Auth::VerifyOtpChallengeToken.new(otp).call).to eq(user)

      destroy = Users::IssueDestroyToken.new(user).call
      expect(Users::VerifyDestroyToken.new(destroy).call.user).to eq(user)

      link = Auth::IssueAccountLinkToken.new(user, provider: 'apple', uid: 'apple-1').call
      result = Auth::VerifyAccountLinkToken.new(link).call
      expect(result.user).to eq(user)
      expect(result.provider).to eq('apple')
    end
  end
end
