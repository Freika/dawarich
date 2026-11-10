# frozen_string_literal: true

module Dawarich
  class MetricsBasicAuth
    REALM = 'Dawarich Metrics'

    def initialize(app)
      @app = app
    end

    def call(env)
      auth = Rack::Auth::Basic::Request.new(env)

      return unauthorized unless auth.provided? && auth.basic? && auth.credentials &&
                                 authorized?(*auth.credentials)

      @app.call(env)
    end

    private

    def authorized?(username, password)
      # Fail closed: when either credential is unset/blank the endpoint must not be
      # world-readable (empty Basic credentials would otherwise compare equal).
      return false if METRICS_USERNAME.to_s.empty? || METRICS_PASSWORD.to_s.empty?

      ActiveSupport::SecurityUtils.secure_compare(username.to_s, METRICS_USERNAME.to_s) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, METRICS_PASSWORD.to_s)
    end

    def unauthorized
      [401, { 'Content-Type' => 'text/plain', 'WWW-Authenticate' => %(Basic realm="#{REALM}") }, ['Unauthorized']]
    end
  end
end
