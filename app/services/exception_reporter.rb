# frozen_string_literal: true

class ExceptionReporter
  def self.call(exception, human_message = 'Exception reported')
    return if DawarichSettings.self_hosted?

    if exception.is_a?(Exception)
      Rails.logger.error "#{human_message}: #{exception.message}"
      Sentry.capture_exception(exception)
    else
      Rails.logger.error "#{exception}: #{human_message}"
      Sentry.capture_message("#{exception}: #{human_message}")
    end
  end
end
