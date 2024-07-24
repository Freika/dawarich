# frozen_string_literal: true

class Visit < ApplicationRecord
  belongs_to :area
  belongs_to :user
  has_many :points, dependent: :nullify

  validates :started_at, :ended_at, :duration, :name, :status, presence: true

  enum status: { pending: 0, confirmed: 1, declined: 2 }
end
