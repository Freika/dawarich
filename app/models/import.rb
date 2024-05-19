# frozen_string_literal: true

class Import < ApplicationRecord
  self.ignored_columns = %w[raw_data]

  belongs_to :user
  has_many :points, dependent: :destroy

  include ImportUploader::Attachment(:raw)

  enum source: { google_semantic_history: 0, owntracks: 1, google_records: 2 }
end
