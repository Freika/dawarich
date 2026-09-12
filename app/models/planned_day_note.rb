# frozen_string_literal: true

class PlannedDayNote < ApplicationRecord
  belongs_to :planned_day

  validates :body, :position, presence: true
end
