# frozen_string_literal: true

class Users::Digests::Trial::SchedulingJob < ApplicationJob
  queue_as :digests

  MAX_PER_RUN = 500
  WINDOW = 2.days

  def perform
    cohort = eligible_users.limit(MAX_PER_RUN + 1).pluck(:id)

    user_ids = truncate(cohort)
    return if user_ids.empty?

    ActiveJob.perform_all_later(
      user_ids.map { |user_id| Users::Digests::Trial::CalculatingJob.new(user_id) }
    )
  end

  private

  def eligible_users
    ::User.where(status: :trial).where(active_until: window)
  end

  def window
    Time.current..(Time.current + WINDOW)
  end

  def truncate(cohort)
    return cohort if cohort.size <= MAX_PER_RUN

    Rails.logger.warn(
      "Users::Digests::Trial::SchedulingJob exceeded MAX_PER_RUN (#{MAX_PER_RUN}); cohort truncated"
    )

    cohort.first(MAX_PER_RUN)
  end
end
