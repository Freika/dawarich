# frozen_string_literal: true

# PostHog Rails Initializer
# Place this file in config/initializers/posthog.rb

return if DawarichSettings.self_hosted?
return if ENV['POSTHOG_API_KEY'].blank?

# ============================================================================
# RAILS-SPECIFIC CONFIGURATION
# ============================================================================
# Configure Rails-specific options via PostHog::Rails.configure
# These settings control how PostHog integrates with Rails features.

PostHog::Rails.configure do |config|
  # Automatically capture exceptions (default: false)
  # Set to true to enable automatic exception tracking
  config.auto_capture_exceptions = true

  # Report exceptions that Rails rescues (e.g., with rescue_from) (default: false)
  # Set to true to capture rescued exceptions
  config.report_rescued_exceptions = true

  # Automatically instrument ActiveJob background jobs (default: false)
  # Set to true to enable automatic ActiveJob exception tracking
  config.auto_instrument_active_job = true

  # Use PostHog tracing headers for request-scoped identity/session context (default: true)
  # Request metadata (current URL, method, path, user agent, and IP) is always captured during Rails requests
  # Set to false to ignore client-supplied X-PostHog-Distinct-Id and X-PostHog-Session-Id headers
  # config.use_tracing_headers = true

  # Capture authenticated user context with exceptions (default: true)
  # Authenticated Rails user context takes precedence over client-supplied tracing headers for exception identity
  config.capture_user_context = true

  # Controller method name to get current user (default: :current_user)
  # Exceptions are tagged with the user's id (distinct_id) only — no email or name.
  config.current_user_method = :current_user

  # Additional exception classes to exclude from reporting
  # These are added to the default excluded exceptions
  # config.excluded_exceptions = [
  #   # 'MyCustom404Error',
  #   # 'MyCustomValidationError'
  # ]
end

# You can also configure Rails options directly:
# PostHog::Rails.config.auto_capture_exceptions = true

# ============================================================================
# CORE POSTHOG CONFIGURATION
# ============================================================================
# Initialize the PostHog client with core SDK options.
# IMPORTANT: Use PostHog.init once — creating multiple clients can cause dropped events.
# PostHog.init provides a singleton-like pattern; use PostHog.capture, PostHog.identify, etc.

PostHog.init do |config|
  # ============================================================================
  # REQUIRED CONFIGURATION
  # ============================================================================

  # Your PostHog project API key (required)
  # Get this from: PostHog Project Settings > API Keys
  # https://app.posthog.com/settings/project-details#variables
  config.api_key = ENV.fetch('POSTHOG_API_KEY', nil)

  # ============================================================================
  # OPTIONAL CONFIGURATION
  # ============================================================================

  # For PostHog Cloud, use: https://us.i.posthog.com or https://eu.i.posthog.com
  config.host = ENV.fetch('POSTHOG_HOST', 'https://eu.i.posthog.com')

  # Personal API key (optional, but required for local feature flag evaluation)
  # Get this from: PostHog Settings > Personal API Keys
  # https://app.posthog.com/settings/user-api-keys
  config.personal_api_key = ENV.fetch('POSTHOG_PERSONAL_API_KEY', nil)

  # Maximum number of events to queue before dropping (default: 10000)
  config.max_queue_size = 10_000

  # Feature flags polling interval in seconds (default: 30)
  config.feature_flags_polling_interval = 30

  # Feature flag request timeout in seconds (default: 3)
  config.feature_flag_request_timeout_seconds = 3

  # Error callback - called when PostHog encounters an error
  # config.on_error = proc { |status, message|
  #   Rails.logger.error("[PostHog] Error #{status}: #{message}")
  # }

  # Before send callback - modify or filter events before sending
  # Return nil to prevent the event from being sent
  # config.before_send = proc { |event|
  #   # Filter out test users
  #   return nil if event[:properties]&.dig('$user_email')&.end_with?('@test.com')
  #
  #   # Add custom properties to all events
  #   event[:properties] ||= {}
  #   event[:properties]['environment'] = Rails.env
  #
  #   event
  # }

  # ============================================================================
  # ENVIRONMENT-SPECIFIC CONFIGURATION
  # ============================================================================

  # Disable in test environment
  config.test_mode = true if Rails.env.test?

  # Optional: Disable in development
  # config.test_mode = true if Rails.env.test? || Rails.env.development?
end

# ============================================================================
# DEFAULT EXCLUDED EXCEPTIONS
# ============================================================================
# The following exceptions are excluded by default:
#
# - AbstractController::ActionNotFound
# - ActionController::BadRequest
# - ActionController::InvalidAuthenticityToken
# - ActionController::InvalidCrossOriginRequest
# - ActionController::MethodNotAllowed
# - ActionController::NotImplemented
# - ActionController::ParameterMissing
# - ActionController::RoutingError
# - ActionController::UnknownFormat
# - ActionController::UnknownHttpMethod
# - ActionDispatch::Http::Parameters::ParseError
# - ActiveRecord::RecordNotFound
# - ActiveRecord::RecordNotUnique
#
# These can be re-enabled by removing them from the exclusion list if needed.
