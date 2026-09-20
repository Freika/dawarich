# frozen_string_literal: true

class DeviseMailer < Devise::Mailer
  protected

  def devise_mail(record, action, opts = {}, &block)
    locale = record.respond_to?(:preferred_locale) ? record.preferred_locale : nil

    I18n.with_locale(locale || I18n.locale) do
      super(record, action, opts, &block)
    end
  end
end
