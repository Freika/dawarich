# frozen_string_literal: true

class Lite::ArchivalWarningJob < ApplicationJob
  queue_as :archival

  # Thresholds checked daily for all Lite users.
  # Each threshold defines the cutoff duration and a dedup key.
  THRESHOLDS = [
    { duration: DawarichSettings::LITE_DATA_WINDOW - 1.month,            key: '11mo',   action: :notify_approaching },
    { duration: DawarichSettings::LITE_DATA_WINDOW - 1.month + 15.days,  key: '11_5mo', action: :notify_email },
    { duration: DawarichSettings::LITE_DATA_WINDOW,                      key: '12mo',   action: :notify_archived }
  ].freeze

  def perform
    return if DawarichSettings.self_hosted?

    User.where(plan: :lite).find_each do |user|
      next if user.full_access?

      I18n.with_locale(user.locale) { check_thresholds(user) }
    end
  end

  private

  def check_thresholds(user)
    warnings_sent = user.settings&.dig('archival_warnings') || {}
    oldest_timestamp = user.points.minimum(:timestamp)
    return unless oldest_timestamp

    # Find all crossed thresholds that haven't been sent yet
    unsent_crossed = THRESHOLDS.select do |threshold|
      cutoff = threshold[:duration].ago.to_i
      oldest_timestamp <= cutoff && warnings_sent[threshold[:key]].blank?
    end

    return if unsent_crossed.empty?

    # Only send the most severe (last in the ordered list), mark all as sent
    most_severe = unsent_crossed.last
    send(most_severe[:action], user)
    unsent_crossed.each { |threshold| mark_warning_sent(user, threshold[:key]) }
  end

  def notify_approaching(user)
    I18n.with_locale(user.locale) do
      Notification.create!(
        user: user,
        kind: :warning,
        title: I18n.t('jobs.lite.archival_warning_job.your_oldest_data_will_archive_in_30_days'),
        content: I18n.t('jobs.lite.archival_warning_job.your_oldest_month_of_location_data_will_be_archived_soon')
      )
    end
  end

  def notify_email(user)
    Users::MailerSendingJob.perform_later(user.id, 'archival_approaching')
  end

  def notify_archived(user)
    I18n.with_locale(user.locale) do
      Notification.create!(
        user: user,
        kind: :warning,
        title: I18n.t('jobs.lite.archival_warning_job.data_has_been_archived'),
        content: I18n.t('jobs.lite.archival_warning_job.month_of_location_data_has_been_archived_your_archived')
      )
    end
  end

  def mark_warning_sent(user, key)
    # Atomic JSONB merge at the SQL level to avoid read-modify-write race conditions
    # when multiple job workers process the same user concurrently.
    User.where(id: user.id).update_all(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "settings = COALESCE(settings, '{}'::jsonb) || " \
          "jsonb_build_object('archival_warnings', " \
          "COALESCE(settings->'archival_warnings', '{}'::jsonb) || " \
          'jsonb_build_object(?, ?))',
          key, Time.zone.now.iso8601
        ]
      )
    )
  end
end
