# frozen_string_literal: true

module Users
  class PendingPaymentReminderJob < ApplicationJob
    queue_as :default

    REMINDERS = {
      'day_1' => (1.day..1.day + 24.hours),
      'day_3' => (3.days..3.days + 24.hours),
      'day_7' => (7.days..7.days + 24.hours)
    }.freeze

    def perform
      User.where(status: User.statuses[:pending_payment], signup_variant: 'reverse_trial').find_each do |user|
        age = Time.current - user.created_at
        already_sent = user.settings.fetch('pending_payment_reminders', [])

        REMINDERS.each do |key, range|
          next unless range.cover?(age)
          next if already_sent.include?(key)

          Users::MailerSendingJob.perform_later(user.id, "pending_payment_#{key}")
          user.settings['pending_payment_reminders'] = already_sent + [key]
          user.save!
        end
      end
    end
  end
end
