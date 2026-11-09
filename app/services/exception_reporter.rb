# frozen_string_literal: true

class ExceptionReporter
  def self.call(exception, human_message = 'Exception reported')
    is_exception = exception.is_a?(Exception)
    message = is_exception ? "#{human_message}: #{exception.message}" : "#{exception}: #{human_message}"
    Rails.logger.error message
    return if DawarichSettings.self_hosted? || !Sentry.initialized?

    is_exception ? Sentry.capture_exception(exception) : Sentry.capture_message(message)
  end
end
