# frozen_string_literal: true

class State < ApplicationRecord
  belongs_to :country

  validates :name, :country, presence: true
end
