# frozen_string_literal: true

module Signup
  class BucketVariant
    def initialize(user)
      @user = user
    end

    def call
      return 'legacy_trial' if DawarichSettings.self_hosted?

      variant = 'reverse_trial'

      log_event('signup_variant_assigned', user_id: @user.try(:id), variant: variant, source: 'bucket_variant')

      variant
    end

    private

    def log_event(name, **payload)
      Rails.logger.info({ event: name, **payload }.to_json)
    end
  end
end
