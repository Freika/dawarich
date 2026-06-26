# frozen_string_literal: true

require 'openssl'

module SmtpConfig
  ALLOWED_AUTHENTICATIONS = %i[plain login cram_md5 digest_md5 gssapi ntlm xoauth2].freeze
  DEFAULT_TIMEOUT = 5

  def self.smtp_settings(env = ENV)
    {
      address:              env['SMTP_SERVER'],
      port:                 env['SMTP_PORT']&.to_i,
      domain:               env['SMTP_DOMAIN'],
      user_name:            env['SMTP_USERNAME'],
      password:             env['SMTP_PASSWORD'],
      authentication:       authentication(env),
      enable_starttls:      env.fetch('SMTP_STARTTLS', 'true') == 'true',
      open_timeout:         timeout(env, 'SMTP_OPEN_TIMEOUT'),
      read_timeout:         timeout(env, 'SMTP_READ_TIMEOUT'),
      openssl_verify_mode:  openssl_verify_mode(env)
    }
  end

  def self.mailer_url_options(env = ENV)
    {
      host:     env['DOMAIN'],
      protocol: 'https'
    }
  end

  def self.authentication(env)
    raw = env.fetch('SMTP_AUTHENTICATION', 'plain').to_s.strip
    return :plain if raw.empty?

    sym = raw.downcase.to_sym
    return sym if ALLOWED_AUTHENTICATIONS.include?(sym)

    raise ArgumentError,
          "SMTP_AUTHENTICATION=#{raw.inspect} is not supported; expected one of #{ALLOWED_AUTHENTICATIONS.inspect}"
  end
  private_class_method :authentication

  def self.timeout(env, key)
    raw = env[key]
    return DEFAULT_TIMEOUT if raw.nil? || raw.strip.empty?

    raw.to_i
  end
  private_class_method :timeout

  def self.openssl_verify_mode(env)
    env.fetch('SMTP_IGNORE_CERT_ERRORS', 'false') == 'true' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
  end
  private_class_method :openssl_verify_mode
end
