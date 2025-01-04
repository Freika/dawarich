# frozen_string_literal: true

class City < ApplicationRecord
  belongs_to :country
  belongs_to :state, optional: true
  belongs_to :county, optional: true

  validates :name, :country, presence: true
end
