# frozen_string_literal: true

class Country < ApplicationRecord
  has_many :cities, dependent: :destroy

  validates :name, :iso2_code, presence: true
end
