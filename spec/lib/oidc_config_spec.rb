# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OidcConfig do
  let(:base_env) do
    {
      'OIDC_CLIENT_ID' => 'client-abc',
      'OIDC_CLIENT_SECRET' => 'secret-xyz',
      'APPLICATION_URL' => 'https://dawarich.example.com'
    }
  end

  describe '.enabled?' do
    it 'is true when client id and secret are both present' do
      expect(described_class.enabled?(base_env)).to be true
    end

    it 'is false when client id is missing' do
      expect(described_class.enabled?(base_env.merge('OIDC_CLIENT_ID' => ''))).to be false
    end

    it 'is false when client secret is missing' do
      expect(described_class.enabled?(base_env.merge('OIDC_CLIENT_SECRET' => nil))).to be false
    end
  end

  describe '.build' do
    it 'returns nil when OIDC is not configured' do
      expect(described_class.build({})).to be_nil
    end

    it 'builds a discovery-mode config when issuer is present' do
      config = described_class.build(base_env.merge('OIDC_ISSUER' => 'https://auth.example.com'))

      expect(config[:issuer]).to eq('https://auth.example.com')
      expect(config[:discovery]).to be true
      expect(config[:client_options]).not_to have_key(:host)
    end

    it 'strips a trailing /.well-known/openid-configuration from the issuer' do
      config = described_class.build(
        base_env.merge('OIDC_ISSUER' => 'https://auth.example.com/.well-known/openid-configuration')
      )

      expect(config[:issuer]).to eq('https://auth.example.com')
      expect(config[:discovery]).to be true
    end

    it 'strips a trailing slash from the issuer' do
      config = described_class.build(base_env.merge('OIDC_ISSUER' => 'https://auth.example.com/'))

      expect(config[:issuer]).to eq('https://auth.example.com')
    end

    it 'keeps a path-based issuer intact apart from the well-known suffix' do
      config = described_class.build(
        base_env.merge('OIDC_ISSUER' => 'https://idp.example.com/realms/main/.well-known/openid-configuration')
      )

      expect(config[:issuer]).to eq('https://idp.example.com/realms/main')
    end

    it 'builds a manual-mode config when host is present without issuer' do
      env = base_env.merge(
        'OIDC_HOST' => 'auth.example.com',
        'OIDC_PORT' => '8443',
        'OIDC_TOKEN_ENDPOINT' => '/custom/token'
      )

      config = described_class.build(env)

      expect(config).not_to have_key(:discovery)
      expect(config[:client_options][:host]).to eq('auth.example.com')
      expect(config[:client_options][:port]).to eq(8443)
      expect(config[:client_options][:token_endpoint]).to eq('/custom/token')
      expect(config[:client_options][:authorization_endpoint]).to eq('/authorize')
    end

    it 'defaults the redirect URI from APPLICATION_URL' do
      config = described_class.build(base_env)

      expect(config[:client_options][:redirect_uri])
        .to eq('https://dawarich.example.com/users/auth/openid_connect/callback')
    end

    it 'honors an explicit OIDC_REDIRECT_URI' do
      env = base_env.merge('OIDC_REDIRECT_URI' => 'https://other.example.com/cb')

      expect(described_class.build(env)[:client_options][:redirect_uri])
        .to eq('https://other.example.com/cb')
    end

    context 'PKCE' do
      it 'is disabled by default' do
        expect(described_class.build(base_env)[:pkce]).to be false
      end

      it 'is enabled when OIDC_PKCE_ENABLED=true' do
        expect(described_class.build(base_env.merge('OIDC_PKCE_ENABLED' => 'true'))[:pkce]).to be true
      end

      it 'accepts mixed case' do
        expect(described_class.build(base_env.merge('OIDC_PKCE_ENABLED' => 'TRUE'))[:pkce]).to be true
      end

      it 'stays disabled for any non-true value' do
        %w[false 1 yes off].each do |value|
          built = described_class.build(base_env.merge('OIDC_PKCE_ENABLED' => value))
          expect(built[:pkce]).to be(false), "expected pkce to be false when OIDC_PKCE_ENABLED=#{value.inspect}"
        end
      end
    end
  end
end
