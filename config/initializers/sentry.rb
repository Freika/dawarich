# frozen_string_literal: true

return unless SENTRY_DSN

require Rails.root.join('lib/sentry_log_redactor')

sentry_logs_enabled = ENV.fetch('SENTRY_ENABLE_LOGS', 'false').casecmp?('true')

Sentry.init do |config|
  config.breadcrumbs_logger = [:active_support_logger]
  config.dsn = SENTRY_DSN
  config.traces_sample_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', 0.05).to_f
  config.profiles_sample_rate = ENV.fetch('SENTRY_PROFILES_SAMPLE_RATE', 0.1).to_f
  config.rails.structured_logging.enabled = false

  config.before_send_log = ->(log) { SentryLogRedactor.call(log) if sentry_logs_enabled }
end

require Rails.root.join('lib/sentry_logs_logger')

Rails.application.config.after_initialize do
  next unless sentry_logs_enabled
  next unless Sentry.initialized?
  next if Rails.logger.nil?

  sentry_logger = SentryLogsLogger.new(level: ::Logger::INFO)

  if Rails.logger.respond_to?(:broadcast_to)
    Rails.logger.broadcast_to(sentry_logger)
  else
    Rails.logger.extend(ActiveSupport::Logger.broadcast(sentry_logger))
  end
end
