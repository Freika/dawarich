# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(user_id:, start_at:, end_at:)
    user = User.find(user_id)

    time_chunks = (start_at..end_at).step(1.day).to_a

    time_chunks.each do |time_chunk|
      Visits::Suggest.new(user, start_at: time_chunk, end_at: time_chunk + 1.day).call
    end
  end
end
