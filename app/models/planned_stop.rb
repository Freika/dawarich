# frozen_string_literal: true

class PlannedStop < ApplicationRecord
  belongs_to :planned_day

  validates :name, :position, presence: true
end
