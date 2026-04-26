# frozen_string_literal: true

Rails.application.config.after_initialize do
  next if DawarichSettings.self_hosted?
  next if Rails.env.development? || Rails.env.test?
  next if ENV['SUBSCRIPTION_WEBHOOK_SECRET'].present?

  raise 'SUBSCRIPTION_WEBHOOK_SECRET is required in cloud deploys. ' \
        'Manager → Dawarich subscription callbacks will be rejected without it.'
end
