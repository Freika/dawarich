# frozen_string_literal: true

class Lite::ArchivalWarningJob < ApplicationJob
  queue_as :archival

  # Thresholds checked daily for all Lite users.
  # Each threshold defines the cutoff duration and a dedup key.
  THRESHOLDS = [
    { duration: 11.months,            key: '11mo',   action: :notify_approaching },
    { duration: 11.months + 15.days,  key: '11_5mo', action: :notify_email },
    { duration: 12.months,            key: '12mo',   action: :notify_archived }
  ].freeze

  def perform
    User.where(plan: :lite).find_each do |user|
      check_thresholds(user)
    end
  end

  private

  def check_thresholds(user)
    warnings_sent = user.settings&.dig('archival_warnings') || {}
    oldest_timestamp = user.points.minimum(:timestamp)
    return unless oldest_timestamp

    THRESHOLDS.each do |threshold|
      cutoff = threshold[:duration].ago.to_i
      next if oldest_timestamp > cutoff
      next if warnings_sent[threshold[:key]].present?

      send(threshold[:action], user)
      mark_warning_sent(user, threshold[:key])
    end
  end

  def notify_approaching(user)
    Notification.create!(
      user: user,
      kind: :warning,
      title: 'Your oldest data will archive in 30 days',
      content: 'Your oldest month of location data will be archived soon. ' \
               'Upgrade to Pro to keep your full history searchable.'
    )
  end

  def notify_email(user)
    Users::MailerSendingJob.perform_later(user.id, 'archival_approaching')
  end

  def notify_archived(user)
    Notification.create!(
      user: user,
      kind: :warning,
      title: 'Data has been archived',
      content: '1 month of location data has been archived. ' \
               'Your archived data is still visible on the map and can be exported at any time. ' \
               'Upgrade to Pro to make it fully searchable and interactive again.'
    )
  end

  def mark_warning_sent(user, key)
    warnings = user.settings&.dig('archival_warnings') || {}
    warnings[key] = Time.zone.now.iso8601
    user.update_column(
      :settings,
      (user.settings || {}).merge('archival_warnings' => warnings)
    )
  end
end
