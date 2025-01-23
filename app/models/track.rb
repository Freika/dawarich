# frozen_string_literal: true

class Track < ApplicationRecord
  belongs_to :user

  validates :path, :started_at, :ended_at, presence: true
end
