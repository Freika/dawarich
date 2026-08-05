# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV['SMTP_FROM']
  layout 'mailer'

  around_action :switch_locale

  rescue_from ActiveJob::DeserializationError do |exception|
    Rails.logger.info("[ApplicationMailer] discarding delivery for a missing record: #{exception.message}")
  end

  private

  def switch_locale(&block)
    I18n.with_locale(params[:user]&.preferred_locale || I18n.locale, &block)
  end
end
