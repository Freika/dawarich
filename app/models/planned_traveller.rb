# frozen_string_literal: true

class PlannedTraveller < ApplicationRecord
  belongs_to :trip

  validates :name, presence: true
end
