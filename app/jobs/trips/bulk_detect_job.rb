# frozen_string_literal: true

# The daily Trip Detection run: one Trips::DetectJob for every user with a Home.
class Trips::BulkDetectJob < ApplicationJob
  queue_as :trips

  def perform
    ActiveJob.perform_all_later(Home.distinct.pluck(:user_id).map { |user_id| Trips::DetectJob.new(user_id) })
  end
end
