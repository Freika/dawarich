class Stat < ApplicationRecord
  validates :year, :month, presence: true

  belongs_to :user
end
