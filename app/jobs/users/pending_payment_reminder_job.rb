# frozen_string_literal: true

module Users
  class PendingPaymentReminderJob < ApplicationJob
    queue_as :default

    THRESHOLDS = {
      1 => 'pending_payment_day_1',
      3 => 'pending_payment_day_3',
      7 => 'pending_payment_day_7'
    }.freeze

    def perform
      User.where(status: User.statuses[:pending_payment], signup_variant: 'reverse_trial').find_each do |user|
        process_user(user)
      end
    end

    private

    def process_user(user)
      age_days = ((Time.current - user.created_at) / 1.day).floor

      user.with_lock do
        # Reload under the lock so we see fresh settings and avoid overwriting a
        # concurrent update.
        user.reload

        sent = normalized_reminders(user.settings['pending_payment_reminders'])
        pending = THRESHOLDS.select { |day, _| age_days >= day && !sent[day.to_s] }

        next if pending.empty?

        merged = sent.dup
        pending.each_key { |day| merged[day.to_s] = true }

        new_settings = user.settings.merge('pending_payment_reminders' => merged)
        user.update!(settings: new_settings)

        pending.each_value do |email_type|
          Users::MailerSendingJob.perform_later(user.id, email_type)
        end
      end
    end

    # Accepts both new hash format ({ '1' => true, '3' => true }) and
    # legacy array format (['day_1', 'day_3']). Returns normalized hash.
    def normalized_reminders(raw)
      case raw
      when Hash  then raw
      when Array then raw.each_with_object({}) { |v, h| h[v.to_s.sub('day_', '')] = true if v.is_a?(String) }
      else            {}
      end
    end
  end
end
