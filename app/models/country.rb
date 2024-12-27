# frozen_string_literal: true

class Country < ApplicationRecord
  validates :name, :iso2_code, presence: true
end
