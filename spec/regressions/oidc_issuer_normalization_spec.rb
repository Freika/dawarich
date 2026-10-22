# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OIDC issuer normalization' do
  # An issuer identifier carries no fragment, so a pasted discovery URL written
  # with "#" has to collapse back to the bare issuer. A trailing slash that the
  # provider actually publishes must survive, because some do (Auth0, Authentik).
  {
    'https://auth.example.com/#.well-known/openid-configuration' => 'https://auth.example.com',
    'https://auth.example.com#.well-known/openid-configuration' => 'https://auth.example.com',
    'https://auth.example.com:8443/#.well-known/openid-configuration' => 'https://auth.example.com:8443',
    'http://[::1]:9000/#.well-known/openid-configuration' => 'http://[::1]:9000',
    'https://auth.example.com  # inline note' => 'https://auth.example.com',
    'https://auth.example.com/application/o/dawarich/#.well-known/openid-configuration' =>
      'https://auth.example.com/application/o/dawarich/',
    'https://tenant.auth0.com/' => 'https://tenant.auth0.com/',
    'https://tenant.auth0.com/ # sso' => 'https://tenant.auth0.com/',
    'https://auth.example.com/application/o/dawarich/' => 'https://auth.example.com/application/o/dawarich/'
  }.each do |configured, expected|
    it "normalizes #{configured.inspect} to #{expected.inspect}" do
      expect(OidcConfig.normalize_issuer(configured)).to eq(expected)
    end
  end

  it 'uses the normalized issuer when building the omniauth config' do
    env = {
      'OIDC_CLIENT_ID' => 'client-abc',
      'OIDC_CLIENT_SECRET' => 'secret-xyz',
      'APPLICATION_URL' => 'https://dawarich.example.com',
      'OIDC_ISSUER' => 'https://auth.example.com/#.well-known/openid-configuration'
    }

    config = OidcConfig.build(env)

    expect(config[:issuer]).to eq('https://auth.example.com')
    expect(config[:discovery]).to be true
  end

  it 'does not enable discovery when the issuer is nothing but a fragment' do
    env = {
      'OIDC_CLIENT_ID' => 'client-abc',
      'OIDC_CLIENT_SECRET' => 'secret-xyz',
      'APPLICATION_URL' => 'https://dawarich.example.com',
      'OIDC_HOST' => 'auth.example.com',
      'OIDC_ISSUER' => '#.well-known/openid-configuration'
    }

    config = OidcConfig.build(env)

    expect(config).not_to have_key(:issuer)
    expect(config[:discovery]).to be_nil
    expect(config[:client_options][:host]).to eq('auth.example.com')
  end
end
