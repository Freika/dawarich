# frozen_string_literal: true

class ExceptionReporter
  def self.call(exception, human_message = 'Exception reported')
    if exception.is_a?(Exception)
      Rails.logger.error "#{human_message}: #{exception.message}"
      return if DawarichSettings.self_hosted?

      Sentry.capture_exception(exception) if Sentry.initialized?
    else
      Rails.logger.error "#{exception}: #{human_message}"
      return if DawarichSettings.self_hosted?

      Sentry.capture_message("#{exception}: #{human_message}") if Sentry.initialized?
    end
  end
end
