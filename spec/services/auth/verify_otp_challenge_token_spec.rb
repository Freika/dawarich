# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::VerifyOtpChallengeToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it 'returns the user for a valid token' do
    token = Auth::IssueOtpChallengeToken.new(user).call
    expect(described_class.new(token).call).to eq(user)
  end

  it 'raises for an expired token' do
    token = Auth::IssueOtpChallengeToken.new(user).call
    travel_to(6.minutes.from_now) do
      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
    end
  end

  it 'raises for a token with the wrong purpose' do
    wrong_token = JWT.encode(
      { user_id: user.id, purpose: 'something_else', exp: 5.minutes.from_now.to_i },
      ENV['JWT_SECRET_KEY'], 'HS256'
    )
    expect { described_class.new(wrong_token).call }.to raise_error(described_class::InvalidToken)
  end

  it 'raises for a token signed with a different secret' do
    wrong_token = JWT.encode(
      { user_id: user.id, purpose: 'otp_challenge', exp: 5.minutes.from_now.to_i },
      'wrong-secret', 'HS256'
    )
    expect { described_class.new(wrong_token).call }.to raise_error(described_class::InvalidToken)
  end

  it 'raises when the user no longer exists' do
    token = Auth::IssueOtpChallengeToken.new(user).call
    user.destroy
    expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
  end

  describe 'replay protection' do
    it 'raises TokenReplayed when the token jti has been marked consumed' do
      token = Auth::IssueOtpChallengeToken.new(user).call
      decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
      Rails.cache.write("otp_challenge:consumed:#{decoded['jti']}", true, expires_in: 5.minutes)

      expect { described_class.new(token).call }.to raise_error(described_class::TokenReplayed)
    end

    it 'TokenReplayed is a kind of InvalidToken so existing rescuers still catch it' do
      expect(described_class::TokenReplayed.new).to be_a(described_class::InvalidToken)
    end
  end

  describe 'issue-time defense-in-depth' do
    it 'rejects a token whose iat is older than the TTL even if exp is still live' do
      old_iat = (Auth::IssueOtpChallengeToken::TTL.ago - 1.minute).to_i
      token = JWT.encode(
        { user_id: user.id, purpose: 'otp_challenge',
          jti: SecureRandom.uuid, iat: old_iat,
          exp: 10.minutes.from_now.to_i },
        ENV['JWT_SECRET_KEY'], 'HS256'
      )
      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
    end
  end
end
