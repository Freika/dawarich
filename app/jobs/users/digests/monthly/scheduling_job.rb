# frozen_string_literal: true

class Users::Digests::Monthly::SchedulingJob < ApplicationJob
  queue_as :digests

  def perform
    target = 1.month.ago
    year   = target.year
    month  = target.month

    jobs = ::User.active_or_trial.find_each.filter_map do |user|
      next unless user.safe_settings.monthly_digest_emails_enabled?
      next unless user.stats.where(year: year, month: month).exists?

      Users::Digests::Monthly::CalculatingJob.new(user.id, year, month)
    end

    ActiveJob.perform_all_later(jobs)
  end
end
