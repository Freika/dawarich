# frozen_string_literal: true

class PlannedAccommodation < ApplicationRecord
  belongs_to :trip

  validates :name, presence: true
end
