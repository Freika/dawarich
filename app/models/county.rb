# frozen_string_literal: true

class County < ApplicationRecord
  belongs_to :country
  belongs_to :state, optional: true

  validates :name, :country, presence: true
end
