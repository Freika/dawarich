# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::VerifyAccountLinkToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def issue(provider: 'apple', uid: 'apple-sub-123')
    Auth::IssueAccountLinkToken.new(user, provider: provider, uid: uid).call
  end

  it 'returns the user, provider, uid, and jti for a valid token' do
    token = issue
    result = described_class.new(token).call

    expect(result.user).to eq(user)
    expect(result.provider).to eq('apple')
    expect(result.uid).to eq('apple-sub-123')
    expect(result.jti).to be_present
  end

  it 'raises for a token with the wrong purpose' do
    wrong = JWT.encode(
      { user_id: user.id, purpose: 'something_else',
        provider: 'apple', uid: 'x', jti: SecureRandom.uuid,
        exp: 5.minutes.from_now.to_i },
      ENV.fetch('JWT_SECRET_KEY', 'test_secret'), 'HS256'
    )

    expect { described_class.new(wrong).call }.to raise_error(described_class::InvalidToken)
  end

  it 'raises for a token signed with a different secret' do
    wrong = JWT.encode(
      { user_id: user.id, purpose: 'oauth_account_link',
        provider: 'apple', uid: 'x', jti: SecureRandom.uuid,
        exp: 5.minutes.from_now.to_i },
      'wrong-secret', 'HS256'
    )

    expect { described_class.new(wrong).call }.to raise_error(described_class::InvalidToken)
  end

  it 'raises TokenReplayed when the jti has been marked consumed' do
    token = issue
    payload = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, algorithm: 'HS256').first
    Rails.cache.write("oauth_account_link:consumed:#{payload['jti']}", true, expires_in: 15.minutes)

    expect { described_class.new(token).call }.to raise_error(described_class::TokenReplayed)
  end

  it 'raises for an expired token' do
    token = issue
    travel_to(16.minutes.from_now) do
      expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
    end
  end

  it 'raises when the user has been deleted' do
    token = issue
    user.destroy
    expect { described_class.new(token).call }.to raise_error(described_class::InvalidToken)
  end

  describe '.mark_consumed!' do
    it 'writes the jti to cache so replays are rejected' do
      described_class.mark_consumed!('test-jti')
      expect(Rails.cache.exist?('oauth_account_link:consumed:test-jti')).to be(true)
    end

    it 'is a no-op for a blank jti' do
      described_class.mark_consumed!('')
      expect(Rails.cache.exist?('oauth_account_link:consumed:')).to be(false)
    end
  end
end
