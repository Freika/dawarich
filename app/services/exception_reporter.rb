# frozen_string_literal: true

class ExceptionReporter
  def self.call(exception, human_message = 'Exception reported', context = {})
    return unless DawarichSettings.self_hosted?

    Rails.logger.error "#{human_message}: #{exception.message}"

    Sentry.capture_exception(exception)
  end
end
