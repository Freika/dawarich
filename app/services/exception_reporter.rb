# frozen_string_literal: true

class ExceptionReporter
  def self.call(exception)
    return unless DawarichSettings.self_hosted?

    Rails.logger.error "Exception: #{exception.message}"

    Sentry.capture_exception(exception)
  end
end
