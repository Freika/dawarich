class Device < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: { scope: :user_id }
end
