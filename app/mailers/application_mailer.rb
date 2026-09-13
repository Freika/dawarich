# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV['SMTP_FROM']
  layout 'mailer'

  around_action :use_recipient_locale

  rescue_from ActiveJob::DeserializationError do |exception|
    Rails.logger.info("[ApplicationMailer] discarding delivery for a missing record: #{exception.message}")
  end

  private

  def use_recipient_locale(&action)
    I18n.with_locale(params&.[](:user)&.preferred_locale || I18n.locale, &action)
  end

  def with_user_locale(user, &action)
    I18n.with_locale(user&.preferred_locale || I18n.locale, &action)
  end
end
