# frozen_string_literal: true

return unless SENTRY_DSN

Sentry.init do |config|
  config.breadcrumbs_logger = [:active_support_logger]
  config.dsn = SENTRY_DSN
  config.traces_sample_rate = 1.0
  config.profiles_sample_rate = 1.0
  # config.enable_logs = true
end
