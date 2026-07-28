# frozen_string_literal: true

module SmtpConfig
  ALLOWED_AUTHENTICATIONS = %i[plain login cram_md5 digest_md5 gssapi ntlm xoauth2].freeze
  NO_AUTHENTICATION_VALUES = %w[none nil false off disabled].freeze
  DEFAULT_TIMEOUT = 5

  IMPLICIT_TLS_PORT = 465

  def self.smtp_settings(env = ENV)
    ssl = ssl?(env)

    {
      address:         env['SMTP_SERVER'],
      port:            env['SMTP_PORT']&.to_i,
      domain:          env['SMTP_DOMAIN'],
      user_name:       env['SMTP_USERNAME'],
      password:        env['SMTP_PASSWORD'],
      authentication:  authentication(env),
      ssl:             ssl,
      enable_starttls: !ssl && env.fetch('SMTP_STARTTLS', 'true') == 'true',
      open_timeout:    timeout(env, 'SMTP_OPEN_TIMEOUT'),
      read_timeout:    timeout(env, 'SMTP_READ_TIMEOUT')
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

    normalized = raw.downcase
    return nil if NO_AUTHENTICATION_VALUES.include?(normalized)

    sym = normalized.to_sym
    return sym if ALLOWED_AUTHENTICATIONS.include?(sym)

    raise ArgumentError,
          "SMTP_AUTHENTICATION=#{raw.inspect} is not supported; expected one of " \
          "#{ALLOWED_AUTHENTICATIONS.inspect} or 'none' to disable authentication"
  end
  private_class_method :authentication

  def self.ssl?(env)
    raw = env['SMTP_SSL'].to_s.strip
    return raw == 'true' unless raw.empty?

    env['SMTP_PORT']&.to_i == IMPLICIT_TLS_PORT
  end
  private_class_method :ssl?

  def self.timeout(env, key)
    raw = env[key]
    return DEFAULT_TIMEOUT if raw.nil? || raw.strip.empty?

    raw.to_i
  end
  private_class_method :timeout
end
