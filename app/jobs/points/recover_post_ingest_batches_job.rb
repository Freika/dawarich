# frozen_string_literal: true

class Points::RecoverPostIngestBatchesJob < ApplicationJob
  queue_as :points

  BATCH_SIZE = 100

  def perform
    Points::PostIngestBatch.order(:id).limit(BATCH_SIZE).each do |batch|
      Points::PostIngestActions.new(
        user_id: batch.user_id,
        timestamps: [batch.start_at, batch.end_at],
        points: [],
        payload: [],
        batch:
      ).call
    end
  end
end
