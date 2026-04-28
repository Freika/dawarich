# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::IssueOtpChallengeToken do
  let(:user) { create(:user) }

  it 'returns a JWT that decodes to the expected payload' do
    token = described_class.new(user).call
    decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    expect(decoded['user_id']).to eq(user.id)
    expect(decoded['purpose']).to eq('otp_challenge')
    expect(decoded['exp']).to be > Time.now.to_i
  end

  it 'expires in 5 minutes' do
    token = described_class.new(user).call
    decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    expect(decoded['exp']).to be_within(5).of(5.minutes.from_now.to_i)
  end

  it 'includes a unique jti claim on every issuance' do
    decoded_a = JWT.decode(described_class.new(user).call, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    decoded_b = JWT.decode(described_class.new(user).call, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    expect(decoded_a['jti']).to be_present
    expect(decoded_b['jti']).to be_present
    expect(decoded_a['jti']).not_to eq(decoded_b['jti'])
  end

  it 'includes an iat claim (issued-at) for defense-in-depth replay checks' do
    token = described_class.new(user).call
    decoded = JWT.decode(token, ENV['JWT_SECRET_KEY'], true, algorithm: 'HS256').first
    expect(decoded['iat']).to be_within(5).of(Time.now.to_i)
  end
end
