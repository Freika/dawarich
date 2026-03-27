# frozen_string_literal: true

class Points::AnomalyFilterJob < ApplicationJob
  queue_as :default

  def perform(user_id, start_time, end_time)
    Points::AnomalyFilter.new(user_id, start_time, end_time).call
  end
end
