# frozen_string_literal: true

class Users::Digests::Yearly::SchedulingJob < ApplicationJob
  queue_as :digests

  def perform
    year = 1.year.ago.year # Previous year's digest

    jobs = ::User.active_or_trial.find_each.filter_map do |user|
      next unless user.safe_settings.yearly_digest_emails_enabled?
      next unless user.stats.where(year: year).exists?

      # Email is chained from the calculating job
      Users::Digests::Yearly::CalculatingJob.new(user.id, year)
    end

    ActiveJob.perform_all_later(jobs)
  end
end
