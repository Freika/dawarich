class Import < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :destroy

  has_one_attached :file

  enum source: { google: 0, owntracks: 1 }
end
