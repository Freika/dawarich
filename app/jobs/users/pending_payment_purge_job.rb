# frozen_string_literal: true

module Users
  class PendingPaymentPurgeJob < ApplicationJob
    queue_as :default

    def perform
      User.where(status: User.statuses[:pending_payment], signup_variant: 'reverse_trial')
          .where('created_at < ?', 30.days.ago)
          .find_each do |user|
            destroy_if_still_eligible(user)
          end
    end

    private

    def destroy_if_still_eligible(user)
      user.with_lock do
        # Re-check inside the lock: the user may have completed payment via webhook
        # between our SELECT and this row being picked up.
        return unless user.pending_payment?
        return unless user.signup_variant == 'reverse_trial'
        return unless user.created_at < 30.days.ago

        Users::Destroy.new(user).call
      end
    end
  end
end
