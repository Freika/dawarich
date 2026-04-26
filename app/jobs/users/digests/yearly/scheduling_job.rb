# frozen_string_literal: true

class Users::Digests::Yearly::SchedulingJob < ApplicationJob
  queue_as :digests

  def perform
    year = Time.current.year - 1 # Previous year's digest

    ::User.active_or_trial.find_each do |user|
      next unless user.safe_settings.yearly_digest_emails_enabled?
      next unless user.stats.where(year: year).exists?

      # Schedule calculation; email is chained from the calculating job
      Users::Digests::Yearly::CalculatingJob.perform_later(user.id, year)
    end
  end
end
