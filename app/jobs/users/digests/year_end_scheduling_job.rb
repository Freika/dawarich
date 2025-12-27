# frozen_string_literal: true

class Users::Digests::YearEndSchedulingJob < ApplicationJob
  queue_as :digests

  def perform
    year = Time.current.year - 1 # Previous year's digest

    ::User.active_or_trial.find_each do |user|
      # Skip if user has no data for the year
      next unless user.stats.where(year: year).exists?

      # Schedule calculation first
      Users::Digests::CalculatingJob.perform_later(user.id, year)

      # Schedule email with delay to allow calculation to complete
      Users::Digests::EmailSendingJob.set(wait: 30.minutes).perform_later(user.id, year)
    end
  end
end
