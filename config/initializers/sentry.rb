# frozen_string_literal: true

return unless SENTRY_DSN

require Rails.root.join('lib/sentry_log_redactor')

Sentry.init do |config|
  config.breadcrumbs_logger = [:active_support_logger]
  config.dsn = SENTRY_DSN
  config.traces_sample_rate = 1.0
  config.profiles_sample_rate = 1.0
  config.enable_logs = Rails.env.production? || Rails.env.staging?

  config.before_send_log = ->(log) { SentryLogRedactor.call(log) }
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
