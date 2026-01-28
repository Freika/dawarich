# frozen_string_literal: true

# Job to recalculate (hard update) stats, tracks, and digests for a user.
# Optionally accepts a year to limit the recalculation scope.
# If no year is provided, recalculates for all tracked years.
class Users::RecalculateDataJob < ApplicationJob
  queue_as :default

  def perform(user_id, year: nil)
    @user = User.find(user_id)
    @year = year&.to_i

    years_to_process = determine_years

    if years_to_process.empty?
      Rails.logger.info "No data to recalculate for user #{user_id}"
      return
    end

    recalculate_stats(years_to_process)
    recalculate_tracks(years_to_process)
    recalculate_digests(years_to_process)

    create_success_notification(years_to_process)
  rescue StandardError => e
    create_failure_notification(e)
    raise
  end

  private

  attr_reader :user, :year

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

      Tracks::ParallelGenerator.new(
        user,
        start_at: start_at,
        end_at: end_at,
        mode: :bulk
      ).call
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
    year_label = years_to_process.size == 1 ? years_to_process.first.to_s : "#{years_to_process.size} years"

    Notifications::Create.new(
      user: user,
      kind: :info,
      title: 'Data recalculation completed',
      content: "Stats, tracks, and digests have been recalculated for #{year_label}."
    ).call
  end

  def create_failure_notification(error)
    Notifications::Create.new(
      user: user,
      kind: :error,
      title: 'Data recalculation failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.first(10).join("\n")}"
    ).call
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
