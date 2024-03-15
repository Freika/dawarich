class Import < ApplicationRecord
  belongs_to :user, dependent: :destroy
  has_many :points, dependent: :destroy

  enum source: { google: 0, owntracks: 1 }
end
