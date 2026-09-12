# frozen_string_literal: true

class PlannedReservation < ApplicationRecord
  belongs_to :trip
  belongs_to :planned_day, optional: true

  validates :title, presence: true
end
