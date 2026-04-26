# frozen_string_literal: true

# Fail-fast for cloud deploys missing SUBSCRIPTION_WEBHOOK_SECRET. Without
# the secret, every Manager → Dawarich callback returns 503 and the user's
# subscription state silently drifts (welcome page crashes, navbar shows
# "Finish signup", plan stays inactive past trial conversion). Catch this
# at boot rather than at request time so a bad deploy never replaces a
# working one.
#
# Self-hosted instances bypass the check — they don't run the Manager
# service and shouldn't ship with this secret set.
Rails.application.config.after_initialize do
  next if DawarichSettings.self_hosted?
  next if Rails.env.development? || Rails.env.test?
  next if ENV['SUBSCRIPTION_WEBHOOK_SECRET'].present?

  raise 'SUBSCRIPTION_WEBHOOK_SECRET is required in cloud deploys. ' \
        'Manager → Dawarich subscription callbacks will be rejected without it.'
end
