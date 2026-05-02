# frozen_string_literal: true

return unless SENTRY_DSN

Sentry.init do |config|
  config.breadcrumbs_logger = [:active_support_logger]
  config.dsn = SENTRY_DSN
  config.traces_sample_rate = 1.0
  config.profiles_sample_rate = 1.0
  config.enable_logs = true

  sensitive_keys = %w[
    password password_confirmation token api_key secret authorization
    access_token refresh_token otp ssn credit_card card_number cvv
  ]
  email_pattern = /[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/

  config.before_send_log = lambda do |log|
    log.attributes.each do |key, value|
      if sensitive_keys.any? { |k| key.to_s.downcase.include?(k) }
        log.attributes[key] = '[FILTERED]'
      elsif value.is_a?(String) && value.match?(email_pattern)
        log.attributes[key] = value.gsub(email_pattern, '[EMAIL]')
      end
    end
    log.body = log.body.gsub(email_pattern, '[EMAIL]') if log.body.is_a?(String)
    log
  end
end

require Rails.root.join('lib/sentry_logs_logger')

Rails.application.config.after_initialize do
  next unless Sentry.initialized?
  next if Rails.logger.nil?

  sentry_logger = SentryLogsLogger.new(level: ::Logger::INFO)

  if Rails.logger.respond_to?(:broadcast_to)
    Rails.logger.broadcast_to(sentry_logger)
  else
    Rails.logger.extend(ActiveSupport::Logger.broadcast(sentry_logger))
  end
end
