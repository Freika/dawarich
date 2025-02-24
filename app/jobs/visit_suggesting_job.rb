# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_ids: [], start_at: 1.day.ago, end_at: Time.current)
    users = user_ids.any? ? User.where(id: user_ids) : User.all

    users.find_each do |user|
      next unless user.active?
      next if user.tracked_points.empty?

      Visits::Suggest.new(user, start_at:, end_at:).call
    end
  end
end
