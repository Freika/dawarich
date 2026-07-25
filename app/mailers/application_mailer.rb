# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV['SMTP_FROM']
  layout 'mailer'

  rescue_from ActiveJob::DeserializationError do |exception|
    Rails.logger.info("[ApplicationMailer] discarding delivery for a missing record: #{exception.message}")
  end
end
