# frozen_string_literal: true

class Users::Digests::Trial::CalculatingJob < ApplicationJob
  queue_as :digests

  TRIAL_WINDOW = 7.days

  def perform(user_id)
    user = ::User.find_by(id: user_id)
    return if user.nil? || user.active_until.blank?

    Time.use_zone(user.timezone.presence || Time.zone.name) do
      Users::Digests::CalculateWeek.new(user.id, range_start(user), Date.current).call
    end
  end

  private

  def range_start(user)
    (user.active_until - TRIAL_WINDOW).to_date
  end
end
