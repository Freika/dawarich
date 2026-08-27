# frozen_string_literal: true

module OidcConfig
  DEFAULT_AUTHORIZATION_ENDPOINT = '/authorize'
  DEFAULT_TOKEN_ENDPOINT = '/token'
  DEFAULT_USERINFO_ENDPOINT = '/userinfo'
  DEFAULT_PORT = 443
  DEFAULT_SCHEME = 'https'

  def self.enabled?(env = ENV)
    env['OIDC_CLIENT_ID'].to_s.strip != '' && (env['OIDC_CLIENT_SECRET'].to_s.strip != '' || pkce_enabled?(env))
  end

  def self.public_client?(env = ENV)
    env['OIDC_CLIENT_SECRET'].to_s.strip == '' && pkce_enabled?(env)
  end

  def self.build(env = ENV)
    return nil unless enabled?(env)

    config = {
      name: :openid_connect,
      scope: %i[openid email profile],
      response_type: :code,
      pkce: pkce_enabled?(env),
      client_options: {
        identifier: env['OIDC_CLIENT_ID'],
        secret: env['OIDC_CLIENT_SECRET'],
        redirect_uri: redirect_uri(env)
      }
    }

    config[:client_auth_method] = :none if public_client?(env)

    issuer = normalize_issuer(env['OIDC_ISSUER'].to_s)

    if issuer != ''
      config[:issuer] = issuer
      config[:discovery] = true
    elsif env['OIDC_HOST'].to_s.strip != ''
      config[:client_options].merge!(manual_endpoints(env))
    end

    config
  end

  # Discovery expects the bare issuer; the gem appends the well-known path
  # itself. Configs pasting the full discovery URL would otherwise request a
  # doubled path and fail with an opaque NoMethodError. An issuer identifier
  # carries no fragment, so anything after "#" is a pasting artefact too.
  def self.normalize_issuer(issuer)
    normalized = issuer.strip
    fragment = normalized.slice!(/#.*\z/m)
    normalized = normalized.strip.sub(%r{/\.well-known/openid-configuration/?\z}, '')

    return normalized unless fragment.to_s.start_with?('#.well-known', '#/.well-known')

    normalized.sub(%r{\A([a-z][a-z0-9+.-]*://[^/]+)/\z}i, '\1')
  end

  def self.pkce_enabled?(env = ENV)
    env['OIDC_PKCE_ENABLED'].to_s.strip.downcase == 'true'
  end

  def self.redirect_uri(env)
    env.fetch('OIDC_REDIRECT_URI') do
      base = env.fetch('APPLICATION_URL', 'http://localhost:3000')
      "#{base}/users/auth/openid_connect/callback"
    end
  end
  private_class_method :redirect_uri

  def self.manual_endpoints(env)
    {
      host: env['OIDC_HOST'],
      scheme: env.fetch('OIDC_SCHEME', DEFAULT_SCHEME),
      port: env.fetch('OIDC_PORT', DEFAULT_PORT).to_i,
      authorization_endpoint: env.fetch('OIDC_AUTHORIZATION_ENDPOINT', DEFAULT_AUTHORIZATION_ENDPOINT),
      token_endpoint: env.fetch('OIDC_TOKEN_ENDPOINT', DEFAULT_TOKEN_ENDPOINT),
      userinfo_endpoint: env.fetch('OIDC_USERINFO_ENDPOINT', DEFAULT_USERINFO_ENDPOINT)
    }
  end
  private_class_method :manual_endpoints
end
