# frozen_string_literal: true

cloud_deploy = !(DawarichSettings.self_hosted? || Rails.env.development? || Rails.env.test?)
if cloud_deploy && ENV['SUBSCRIPTION_WEBHOOK_SECRET'].blank?
  raise 'SUBSCRIPTION_WEBHOOK_SECRET is required in cloud deploys. ' \
        'Manager → Dawarich subscription callbacks will be rejected without it.'
end
