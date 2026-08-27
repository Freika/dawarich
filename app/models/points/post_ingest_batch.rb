# frozen_string_literal: true

class Points::PostIngestBatch < ApplicationRecord
  self.table_name = 'points_post_ingest_batches'

  belongs_to :user

  validates :start_at, :end_at, presence: true
end
