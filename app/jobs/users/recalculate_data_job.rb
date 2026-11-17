# frozen_string_literal: true

# Job to recalculate (hard update) stats, tracks, and digests for a user.
# Optionally accepts a year, or a list of years, to limit the recalculation scope.
# If no year is provided, recalculates for all tracked years.
# `only: 'tracks'` rebuilds just the tracks; `only: 'stats'` just stats and digests.
# `digest_years:` refreshes the digests of further years once the stats are
# rebuilt, since every yearly digest carries all-time totals.
# `anomaly_rebuild: true` marks the rebuild a GPS noise re-check queued: it
# forgets the re-check's fingerprint only once the rebuild has succeeded.
class Users::RecalculateDataJob < ApplicationJob
  include UserTimezone

  queue_as :stats

  retry_on Tracks::PerUserLock::AcquisitionTimeout, wait: :polynomially_longer, attempts: 5 do |job, error|
    user_id, options = job.arguments
    Rails.logger.error(
      'Users::RecalculateDataJob lock contention retries exhausted ' \
      "user_id=#{user_id}: #{error.message}"
    )
    notify = options.is_a?(Hash) ? options.symbolize_keys.fetch(:notify, true) : true
    user = User.find_by(id: user_id) if notify
    if user
      I18n.with_locale(user.locale) do
        content = I18n.t(
          'jobs.users.recalculate_data_job.another_recalculation_is_already_running_please_try_again_in_a'
        )
        Notifications::Create.new(
          user: user, kind: :warning, title: I18n.t('jobs.users.recalculate_data_job.data_recalculation_busy'),
          content: content
        ).call
      end
    end
  end

  ONLY = %w[tracks stats].freeze

  def perform(user_id, year: nil, notify: true, job_queue: nil, only: nil, digest_years: nil, anomaly_rebuild: false)
    @user = find_user_or_skip(user_id) || return
    @only = only.to_s.presence_in(ONLY)

    @years = Array(year).map(&:to_i)
    @notify = notify
    @job_queue = job_queue

    with_user_timezone(user) do
      I18n.with_locale(user.locale) do
        years_to_process = determine_years

        if years_to_process.empty?
          Rails.logger.info "No data to recalculate for user #{user_id}"
          Points::AnomalyRebuildScope.new(user).forget if anomaly_rebuild
          return
        end

        recalculate_stats(years_to_process) unless @only == 'tracks'
        recalculate_tracks(years_to_process) unless @only == 'stats'
        unless @only == 'tracks'
          recalculate_digests(years_to_process)
          recalculate_digests(Array(digest_years).map(&:to_i) - years_to_process)
        end

        create_success_notification(years_to_process) if @notify
      end
    end
    Points::AnomalyRebuildScope.new(user).forget if anomaly_rebuild
  rescue Tracks::PerUserLock::AcquisitionTimeout
    raise
  rescue StandardError => e
    create_failure_notification(e) if @notify
    raise
  end

  private

  attr_reader :user, :years, :job_queue

  def determine_years
    if years.any?
      years
    else
      user.years_tracked.map { |yt| yt[:year] }
    end
  end

  def recalculate_stats(years_to_process)
    years_to_process.each do |y|
      (1..12).each do |month|
        Stats::CalculateMonth.new(user.id, y, month, notify_on_failure: @notify).call
      end
    end

    Rails.logger.info "Recalculated stats for user #{user.id}, years: #{years_to_process.join(', ')}"
  end

  def recalculate_tracks(years_to_process)
    years_to_process.each do |y|
      start_at = Time.zone.local(y, 1, 1).beginning_of_day
      end_at = Time.zone.local(y, 12, 31).end_of_day

      options = { start_at: start_at, end_at: end_at, mode: :bulk }
      options[:job_queue] = job_queue if job_queue

      Tracks::ParallelGenerator.new(user, **options).call
    end

    Rails.logger.info "Recalculated tracks for user #{user.id}, years: #{years_to_process.join(', ')}"
  end

  def recalculate_digests(years_to_process)
    years_to_process.each do |y|
      Users::Digests::CalculateYear.new(user.id, y).call
    end

    Rails.logger.info "Recalculated digests for user #{user.id}, years: #{years_to_process.join(', ')}"
  end

  def create_success_notification(years_to_process)
    I18n.with_locale(user.locale) do
      year_label =
        if years_to_process.size == 1
          years_to_process.first.to_s
        else
          I18n.t('jobs.users.recalculate_data_job.year_count', count: years_to_process.size)
        end

      Notifications::Create.new(
        user: user,
        kind: :info,
        title: I18n.t('jobs.users.recalculate_data_job.data_recalculation_completed'),
        content: I18n.t(
          'jobs.users.recalculate_data_job.stats_tracks_and_digests_have_been_recalculated_for_year_label',
          year_label: year_label
        ),
        action_path: Notifications.paths.stats_path
      ).call
    end
  end

  def create_failure_notification(error)
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user: user,
        kind: :error,
        title: I18n.t('jobs.users.recalculate_data_job.data_recalculation_failed'),
        content: error.message
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
