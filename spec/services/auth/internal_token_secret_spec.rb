# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::InternalTokenSecret do
  it 'A11f OTP secret resolution distinguishes JWT and mobile families without normalizing secrets' do
    fallback = 'a11f-synthetic-rails-fallback'
    mobile = 'a11f-synthetic-mobile-family'
    allow(Rails.application).to receive(:secret_key_base).and_return(fallback)
    contexts = [
      ['a11f-synthetic-jwt-family', 'a11f-synthetic-jwt-family'],
      [nil, fallback], ['', fallback], [" \t\n", fallback],
      ['  a11f-synthetic-padded-jwt  ', '  a11f-synthetic-padded-jwt  ']
    ]
    contexts.each do |configured, expected|
      stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => configured, 'AUTH_JWT_SECRET_KEY' => mobile))
      expect(described_class.call == expected).to be(true)
      token = Auth::IssueOtpChallengeToken.new(create(:user)).call
      expect(JWT.decode(token, expected, true, algorithm: 'HS256').first['purpose']).to eq('otp_challenge')
      expect { JWT.decode(token, mobile, true, algorithm: 'HS256') }.to raise_error(JWT::VerificationError)
      stripped = configured&.strip
      next unless configured.present? && stripped != configured

      expect { JWT.decode(token, stripped, true, algorithm: 'HS256') }.to raise_error(JWT::VerificationError)
    end
    stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => nil, 'AUTH_JWT_SECRET_KEY' => mobile))
    allow(Rails.application).to receive(:secret_key_base).and_return(nil)
    expect(described_class.call).to be_nil
    expect { Auth::IssueOtpChallengeToken.new(create(:user)).call }.to raise_error(JWT::EncodeError)
  end

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
