# frozen_string_literal: true

class PlannedUnplannedPlace < ApplicationRecord
  belongs_to :trip

  validates :name, :position, presence: true
end
