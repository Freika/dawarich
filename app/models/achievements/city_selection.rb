# frozen_string_literal: true

module Achievements
  class CitySelection < ApplicationRecord
    self.table_name = 'achievement_city_selections'
    belongs_to :user
    has_many :collectibles, dependent: :nullify
    validates :territory_code, presence: true, uniqueness: { scope: :user_id }
    after_commit :invalidate_collection

    private

    def invalidate_collection
      CollectionSchedule.call(user)
    end
  end
end
