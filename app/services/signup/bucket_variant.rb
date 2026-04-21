# frozen_string_literal: true

module Signup
  class BucketVariant
    def initialize(user)
      @user = user
    end

    def call
      return 'reverse_trial' if Flipper.enabled?(:reverse_trial_signup, @user)

      'legacy_trial'
    end
  end
end
