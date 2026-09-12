# frozen_string_literal: true

class PlannedDay < ApplicationRecord
  belongs_to :trip
  has_many :planned_stops, -> { order(:position) }, dependent: :destroy, inverse_of: :planned_day
  has_many :planned_day_notes, -> { order(:position) }, dependent: :destroy, inverse_of: :planned_day
  has_many :planned_reservations, dependent: :nullify

  validates :date, :position, presence: true
end
