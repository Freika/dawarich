# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::IssueAccountLinkToken do
  let(:user) { create(:user) }

  def decode(token)
    JWT.decode(token, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), true, algorithm: 'HS256').first
  end

  it 'encodes user_id, provider, uid, purpose, jti, iat, exp' do
    token = described_class.new(user, provider: 'apple', uid: 'apple-123').call
    payload = decode(token)

    expect(payload['user_id']).to eq(user.id)
    expect(payload['provider']).to eq('apple')
    expect(payload['uid']).to eq('apple-123')
    expect(payload['purpose']).to eq('oauth_account_link')
    expect(payload['jti']).to be_present
    expect(payload['iat']).to be_within(5).of(Time.now.to_i)
    expect(payload['exp']).to be_within(5).of(15.minutes.from_now.to_i)
  end

  it 'generates a unique jti per issuance' do
    a = decode(described_class.new(user, provider: 'apple', uid: 'x').call)
    b = decode(described_class.new(user, provider: 'apple', uid: 'x').call)

    expect(a['jti']).not_to eq(b['jti'])
  end
end
