# frozen_string_literal: true

class Trip < ApplicationRecord
  belongs_to :user

  validates :name, :started_at, :ended_at, presence: true
end
