# frozen_string_literal: true

require 'digest'

module Signup
  class BucketVariant
    StableActor = Struct.new(:flipper_id)

    def initialize(user)
      @user = user
    end

    def call
      return 'legacy_trial' if DawarichSettings.self_hosted?

      raise ArgumentError, 'user is required' if @user.nil?

      email = @user.email.to_s.strip
      raise ArgumentError, 'user email must be present for bucketing' if email.empty?

      return 'reverse_trial' if flipper_enabled?(email)

      'legacy_trial'
    end

    private

    def flipper_enabled?(email)
      Flipper.enabled?(:reverse_trial_signup, actor_for(@user, email))
    rescue StandardError => e
      Rails.logger.warn(
        "[Signup::BucketVariant] Flipper unavailable, falling back to legacy_trial: #{e.class}: #{e.message}"
      )
      ExceptionReporter.call(e, '[Signup::BucketVariant] Flipper unavailable, falling back to legacy_trial')
      false
    end

    def actor_for(user, email)
      return user if user.respond_to?(:id) && !user.id.nil?

      StableActor.new(stable_key(email))
    end

    def stable_key(email)
      "User;email-#{Digest::SHA256.hexdigest(email.downcase)}"
    end
  end
end
