# frozen_string_literal: true

class State < ApplicationRecord
  belongs_to :country
  has_many :cities, dependent: :destroy
  has_many :counties, dependent: :destroy

  validates :name, :country, presence: true
end
