# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::VerifyAppleToken do
  let(:bundle_id) { 'app.dawarich.Dawarich' }
  before do
    stub_const('ENV', ENV.to_hash.merge('APPLE_BUNDLE_ID' => bundle_id))
  end

  # Generate a test RSA key + JWKS for signing
  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { 'test-key-id' }
  let(:jwks) do
    {
      keys: [
        {
          kty: 'RSA',
          kid: kid,
          use: 'sig',
          alg: 'RS256',
          n: Base64.urlsafe_encode64(rsa_key.public_key.n.to_s(2), padding: false),
          e: Base64.urlsafe_encode64(rsa_key.public_key.e.to_s(2), padding: false)
        }
      ]
    }.to_json
  end

  before do
    stub_request(:get, 'https://appleid.apple.com/auth/keys').to_return(body: jwks, status: 200)
  end

  def build_token(payload_overrides = {})
    payload = {
      iss: 'https://appleid.apple.com',
      aud: bundle_id,
      sub: '000123.abc456.def789',
      email: 'user@example.com',
      email_verified: 'true',
      exp: 15.minutes.from_now.to_i,
      iat: Time.now.to_i
    }.merge(payload_overrides)
    JWT.encode(payload, rsa_key, 'RS256', { kid: kid })
  end

  it 'returns verified claims for a valid token' do
    claims = described_class.new(build_token).call
    expect(claims[:sub]).to eq('000123.abc456.def789')
    expect(claims[:email]).to eq('user@example.com')
  end

  it 'raises for wrong issuer' do
    token = build_token(iss: 'https://evil.example.com')
    expect { described_class.new(token).call }.to raise_error(Auth::VerifyAppleToken::InvalidToken)
  end

  it 'raises for wrong audience' do
    token = build_token(aud: 'com.evil.app')
    expect { described_class.new(token).call }.to raise_error(Auth::VerifyAppleToken::InvalidToken)
  end

  it 'raises for expired token' do
    token = build_token(exp: 5.minutes.ago.to_i)
    expect { described_class.new(token).call }.to raise_error(Auth::VerifyAppleToken::InvalidToken)
  end

  it 'raises when signature does not match JWKS' do
    other_key = OpenSSL::PKey::RSA.generate(2048)
    token = JWT.encode({ sub: 'x' }, other_key, 'RS256', { kid: kid })
    expect { described_class.new(token).call }.to raise_error(Auth::VerifyAppleToken::InvalidToken)
  end
end
