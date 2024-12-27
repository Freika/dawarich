# frozen_string_literal: true

class City < ApplicationRecord
  belongs_to :country

  validates :name, :country, presence: true
end
