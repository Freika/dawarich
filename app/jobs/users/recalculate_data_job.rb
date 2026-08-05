# frozen_string_literal: true

# Job to recalculate (hard update) stats, tracks, and digests for a user.
# Optionally accepts a year to limit the recalculation scope.
# If no year is provided, recalculates for all tracked years.
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
      I18n.with_locale(user.preferred_locale || I18n.default_locale) do
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

  def perform(user_id, year: nil, notify: true, job_queue: nil)
    @user = find_user_or_skip(user_id) || return

    @year = year&.to_i
    @notify = notify
    @job_queue = job_queue

    with_user_timezone(user) do
      with_user_locale(user) do
        years_to_process = determine_years

        if years_to_process.empty?
          Rails.logger.info "No data to recalculate for user #{user_id}"
          return
        end

        recalculate_stats(years_to_process)
        recalculate_tracks(years_to_process)
        recalculate_digests(years_to_process)

        create_success_notification(years_to_process) if @notify
      end
    end
  rescue Tracks::PerUserLock::AcquisitionTimeout
    raise
  rescue StandardError => e
    create_failure_notification(e) if @notify
    raise
  end

  private

  attr_reader :user, :year, :job_queue

  def determine_years
    if year.present?
      [year]
    else
      user.years_tracked.map { |yt| yt[:year] }
    end
  end

  def recalculate_stats(years_to_process)
    years_to_process.each do |y|
      (1..12).each do |month|
        Stats::CalculateMonth.new(user.id, y, month).call
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
    with_user_locale(user) do
      year_label = if years_to_process.size == 1
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
        )
      ).call
    end
  end

  def create_failure_notification(error)
    with_user_locale(user) do
      Notifications::Create.new(
        user: user,
        kind: :error,
        title: I18n.t('jobs.users.recalculate_data_job.data_recalculation_failed'),
        content: I18n.t('jobs.users.recalculate_data_job.message_stacktrace_n', message: error.message,
                        backtrace: error.backtrace.first(10).join("\n"))
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
