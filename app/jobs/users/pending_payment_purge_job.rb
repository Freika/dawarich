# frozen_string_literal: true

module Users
  class PendingPaymentPurgeJob < ApplicationJob
    queue_as :default

    def perform
      User.where(status: User.statuses[:pending_payment], signup_variant: 'reverse_trial')
          .where('created_at < ?', 30.days.ago)
          .find_each do |user|
            Users::Destroy.new(user).call
          end
    end
  end
end
