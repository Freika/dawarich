# frozen_string_literal: true

class Visit < ApplicationRecord
  belongs_to :area
  belongs_to :user
  has_many :points, dependent: :nullify
end
