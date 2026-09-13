# frozen_string_literal: true

require 'rails_helper'
require 'omniauth/strategies/openid_connect'

RSpec.describe 'OIDC manual endpoints with signed tokens' do
  it 'completes the callback using the configured signing keys without discovery or WebFinger' do
    issuer = 'https://auth.example.test'
    config = OidcConfig.build(
      'OIDC_CLIENT_ID' => 'synthetic-client', 'OIDC_CLIENT_SECRET' => 'synthetic-secret',
      'OIDC_ISSUER' => issuer, 'OIDC_HOST' => 'auth.example.test', 'OIDC_DISCOVERY' => 'false',
      'OIDC_AUTHORIZATION_ENDPOINT' => '/api/oidc/authorization',
      'OIDC_TOKEN_ENDPOINT' => '/api/oidc/token', 'OIDC_USERINFO_ENDPOINT' => '/api/oidc/userinfo',
      'OIDC_JWKS_URI' => "#{issuer}/api/oidc/jwks",
      'OIDC_REDIRECT_URI' => 'http://dawarich.example.test/users/auth/openid_connect/callback'
    )
    app = ->(env) { [200, {}, [env.fetch('omniauth.auth').uid]] }
    strategy = OmniAuth::Strategies::OpenIDConnect.new(app, config)
    session = {}
    env = Rack::MockRequest.env_for('/users/auth/openid_connect').merge('rack.session' => session)
    strategy.instance_variable_set(:@env, env)

    status, headers = strategy.request_phase
    expect(status).to eq(302)
    uri = URI(headers['location'])
    expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq("#{issuer}/api/oidc/authorization")

    key = OpenSSL::PKey::RSA.generate(2048)
    payload = JSON::JWT.new(
      iss: issuer, sub: 'synthetic-user', aud: 'synthetic-client',
      iat: Time.now.to_i, exp: Time.now.to_i + 300, nonce: session.fetch('omniauth.nonce')
    )
    token = payload.sign(key, :RS256).to_s
    stub_request(:get, "#{issuer}/api/oidc/jwks").to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: { keys: [JSON::JWK.new(key.public_key)] }.to_json
    )
    stub_request(:post, "#{issuer}/api/oidc/token").to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: { access_token: 'synthetic-access-token', token_type: 'Bearer', expires_in: 300, id_token: token }.to_json
    )
    stub_request(:get, "#{issuer}/api/oidc/userinfo").to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: { sub: 'synthetic-user', email: 'synthetic@example.test', email_verified: true }.to_json
    )
    callback = "/users/auth/openid_connect/callback?code=synthetic-code&state=#{session.fetch('omniauth.state')}"
    strategy = OmniAuth::Strategies::OpenIDConnect.new(app, config)
    strategy.instance_variable_set(:@env, Rack::MockRequest.env_for(callback).merge('rack.session' => session))

    status, _headers, body = strategy.callback_phase

    expect(status).to eq(200)
    expect(body.join).to eq('synthetic-user')
    expect(a_request(:get, "#{issuer}/api/oidc/jwks")).to have_been_made.once
    expect(a_request(:get, /well-known/)).not_to have_been_made
  end
end
