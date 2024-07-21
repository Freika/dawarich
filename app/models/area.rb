# frozen_string_literal: true

class Area < ApplicationRecord
  belongs_to :user

  validates :name, :latitude, :longitude, :radius, presence: true
end
