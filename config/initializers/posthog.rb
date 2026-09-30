# frozen_string_literal: true

# ProductAnalytics is the only capture path. The Rails integration must not
# emit exceptions, request context, job details, or client-supplied identities.
return if DawarichSettings.self_hosted? || !ProductAnalytics.configured?

PostHog::Rails.configure do |config|
  config.auto_capture_exceptions = false
  config.report_rescued_exceptions = false
  config.auto_instrument_active_job = false
  config.capture_user_context = false
  config.use_tracing_headers = false
end

PostHog.init do |config|
  config.api_key = ENV.fetch('PRODUCT_POSTHOG_API_KEY')
  config.host = ENV.fetch('PRODUCT_POSTHOG_HOST', 'https://eu.i.posthog.com')
  config.personal_api_key = nil
  config.before_send = ->(action) { ProductAnalytics.sanitize_sdk_event(action) }
  config.test_mode = true if Rails.env.test?
end
