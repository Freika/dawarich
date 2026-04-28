# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::IssueDestroyToken do
  let(:user) { create(:user) }
  let(:secret) { ENV.fetch('JWT_SECRET_KEY') }

  it 'issues a JWT with purpose=account_destroy and the user_id' do
    token = described_class.new(user).call
    decoded, = JWT.decode(token, secret, true, algorithm: 'HS256')

    expect(decoded['purpose']).to eq('account_destroy')
    expect(decoded['user_id']).to eq(user.id)
    expect(decoded['jti']).to be_present
    expect(decoded['exp']).to be_within(5).of((Time.now + described_class::TTL).to_i)
  end

  it 'issues a unique jti per call' do
    jti_a = JWT.decode(described_class.new(user).call, secret, false).first['jti']
    jti_b = JWT.decode(described_class.new(user).call, secret, false).first['jti']
    expect(jti_a).not_to eq(jti_b)
  end
end
