# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OIDC issuer normalization' do
  # An issuer identifier carries no fragment, so a pasted discovery URL has to
  # collapse back to the bare issuer. A trailing slash that belongs to a
  # path-based issuer must survive, because some providers publish it.
  {
    'https://auth.example.com' => 'https://auth.example.com',
    'https://auth.example.com/' => 'https://auth.example.com',
    '  https://auth.example.com  ' => 'https://auth.example.com',
    'https://auth.example.com/.well-known/openid-configuration' => 'https://auth.example.com',
    'https://auth.example.com/.well-known/openid-configuration/' => 'https://auth.example.com',
    'https://auth.example.com/#.well-known/openid-configuration' => 'https://auth.example.com',
    'https://auth.example.com#.well-known/openid-configuration' => 'https://auth.example.com',
    'https://auth.example.com:8443/#.well-known/openid-configuration' => 'https://auth.example.com:8443',
    'https://auth.example.com/realms/main/.well-known/openid-configuration' => 'https://auth.example.com/realms/main',
    'https://auth.example.com/application/o/dawarich/' => 'https://auth.example.com/application/o/dawarich/',
    'https://auth.example.com/application/o/dawarich/#.well-known/openid-configuration' =>
      'https://auth.example.com/application/o/dawarich/'
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
end
