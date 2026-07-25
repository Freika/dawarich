# frozen_string_literal: true

class Region < ApplicationRecord
  validates :code, presence: true, uniqueness: true
  validates :geom, presence: true
end
