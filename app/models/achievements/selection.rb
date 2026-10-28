# frozen_string_literal: true

module Achievements
  class Selection < ApplicationRecord
    self.table_name = 'achievement_selections'

    belongs_to :user
    belongs_to :place
    has_many :collectibles, dependent: :nullify

    validates :place_id, uniqueness: { scope: :user_id }
    validate :owned_place
    validate :valid_timezone

    after_commit :schedule_calculation

    private

    def owned_place
      errors.add(:place, :invalid) if place && place.user_id != user_id
    end

    def valid_timezone
      TZInfo::Timezone.get(timezone) if timezone.present?
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:timezone, :invalid)
    end

    def schedule_calculation
      CollectionSchedule.call(user) if user
    end
  end
end
