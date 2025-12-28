RailsPulse.configure do |config|
  # ====================================================================================================
  #                                         GLOBAL CONFIGURATION
  # ====================================================================================================

  # Enable or disable Rails Pulse
  config.enabled = true

  # ====================================================================================================
  #                                               THRESHOLDS
  # ====================================================================================================
  # These thresholds are used to determine if a route, request, or query is slow, very slow, or critical.
  # Values are in milliseconds (ms). Adjust these based on your application's performance requirements.

  # Thresholds for an individual route
  config.route_thresholds = {
    slow:      500,
    very_slow: 1500,
    critical:  3000
  }

  # Thresholds for an individual request
  config.request_thresholds = {
    slow:      700,
    very_slow: 2000,
    critical:  4000
  }

  # Thresholds for an individual database query
  config.query_thresholds = {
    slow:      100,
    very_slow: 500,
    critical:  1000
  }

  # ====================================================================================================
  #                                               FILTERING
  # ====================================================================================================

  # Asset Tracking Configuration
  # By default, Rails Pulse ignores asset requests (images, CSS, JS files) to focus on application performance.
  # Set track_assets to true if you want to monitor asset delivery performance.
  config.track_assets = false

  # Custom asset patterns to ignore (in addition to the built-in defaults)
  # Only applies when track_assets is false. Add patterns for app-specific asset paths.
  config.custom_asset_patterns = [
    # Example: ignore specific asset directories
    # %r{^/uploads/},
    # %r{^/media/},
    # "/special-assets/"
  ]

  # Rails Pulse Mount Path (optional)
  # If Rails Pulse is mounted at a custom path, specify it here to prevent
  # Rails Pulse from tracking its own requests. Leave as nil for default '/rails_pulse'.
  # Examples:
  #   config.mount_path = "/admin/monitoring"
  config.mount_path = nil

  # Manual route filtering
  # Specify additional routes, requests, or queries to ignore from performance tracking.
  # Each array can include strings (exact matches) or regular expressions.
  #
  # Examples:
  #   config.ignored_routes   = ["/health_check", %r{^/admin}]
  #   config.ignored_requests = ["GET /status", %r{POST /api/v1/.*}]
  #   config.ignored_queries  = ["SELECT 1", %r{FROM \"schema_migrations\"}]

  config.ignored_routes   = []
  config.ignored_requests = []
  config.ignored_queries  = []

  # ====================================================================================================
  #                                                 TAGGING
  # ====================================================================================================
  # Define custom tags for categorizing routes, requests, and queries.
  # You can add any custom tags you want for filtering and organization.
  #
  # Tag names should be in present tense and describe the current state or category.
  # Examples of good tag names:
  #   - "critical" (for high-priority endpoints)
  #   - "experimental" (for routes under development)
  #   - "deprecated" (for routes being phased out)
  #   - "external" (for third-party API calls)
  #   - "background" (for async job-related operations)
  #   - "admin" (for administrative routes)
  #   - "public" (for public-facing routes)
  #
  # Example configuration:
  #   config.tags = ["ignored", "critical", "experimental", "deprecated", "external", "admin"]

  config.tags = %w[ignored critical experimental]

  # ====================================================================================================
  #                                            DATABASE CONFIGURATION
  # ====================================================================================================
  # Configure Rails Pulse to use a separate database for performance monitoring data.
  # This is optional but recommended for production applications to isolate performance
  # data from your main application database.
  #
  # Uncomment and configure one of the following patterns:

  # Option 1: Separate single database for Rails Pulse
  # config.connects_to = {
  #   database: { writing: :rails_pulse, reading: :rails_pulse }
  # }

  # Option 2: Primary/replica configuration for Rails Pulse
  # config.connects_to = {
  #   database: { writing: :rails_pulse_primary, reading: :rails_pulse_replica }
  # }

  # Don't forget to add the database configuration to config/database.yml:
  #
  # production:
  #   # ... your main database config ...
  #   rails_pulse:
  #     adapter: postgresql  # or mysql2, sqlite3
  #     database: myapp_rails_pulse_production
  #     username: rails_pulse_user
  #     password: <%= Rails.application.credentials.dig(:rails_pulse, :database_password) %>
  #     host: localhost
  #     pool: 5

  # ====================================================================================================
  #                                            AUTHENTICATION
  # ====================================================================================================
  # Configure authentication to secure access to the Rails Pulse dashboard.
  # Authentication is ENABLED BY DEFAULT in production environments for security.
  #
  # If no authentication method is configured, Rails Pulse will use HTTP Basic Auth
  # with credentials from RAILS_PULSE_USERNAME (default: 'admin') and RAILS_PULSE_PASSWORD
  # environment variables. Set RAILS_PULSE_PASSWORD to enable this fallback.
  #
  # Uncomment and configure one of the following patterns based on your authentication system:

  # Enable/disable authentication (enabled by default in production)
  config.authentication_enabled = true

  # Where to redirect unauthorized users
  # config.authentication_redirect_path = "/"

  # Custom authentication method - choose one of the examples below:

  # Example 1: Devise with admin role check
  config.authentication_method = proc {
    redirect_to main_app.root_path, alert: 'Access denied' unless user_signed_in? && current_user.admin?
  }

  # Example 2: Custom session-based authentication
  # config.authentication_method = proc {
  #   unless session[:user_id] && User.find_by(id: session[:user_id])&.admin?
  #     redirect_to main_app.login_path, alert: "Please log in as an admin"
  #   end
  # }

  # Example 3: Warden authentication
  # config.authentication_method = proc {
  #   warden.authenticate!(:scope => :admin)
  # }

  # Example 4: Basic HTTP authentication
  # config.authentication_method = proc {
  #   authenticate_or_request_with_http_basic do |username, password|
  #     username == ENV['RAILS_PULSE_USERNAME'] && password == ENV['RAILS_PULSE_PASSWORD']
  #   end
  # }

  # Example 5: Custom authorization check
  # config.authentication_method = proc {
  #   current_user = User.find_by(id: session[:user_id])
  #   unless current_user&.can_access_rails_pulse?
  #     render plain: "Forbidden", status: :forbidden
  #   end
  # }

  # ====================================================================================================
  #                                               DATA CLEANUP
  # ====================================================================================================
  # Configure automatic cleanup of old performance data to manage database size.
  # Rails Pulse provides two cleanup mechanisms that work together:
  #
  # 1. Time-based cleanup: Delete records older than the retention period
  # 2. Count-based cleanup: Keep only the specified number of records per table
  #
  # Cleanup order respects foreign key constraints:
  # operations → requests → queries/routes

  # Enable or disable automatic data cleanup
  config.archiving_enabled = true

  # Time-based retention - delete records older than this period
  config.full_retention_period = 2.weeks

  # Count-based retention - maximum records to keep per table
  # After time-based cleanup, if tables still exceed these limits,
  # the oldest remaining records will be deleted to stay under the limit
  config.max_table_records = {
    rails_pulse_requests: 10_000,    # HTTP requests (moderate volume)
    rails_pulse_operations: 50_000,  # Operations within requests (high volume)
    rails_pulse_routes: 1000,       # Unique routes (low volume)
    rails_pulse_queries: 500        # Normalized SQL queries (low volume)
  }
end
