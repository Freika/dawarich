# frozen_string_literal: true

module Achievements
  class Collectible < ApplicationRecord
    self.table_name = 'achievement_collectibles'
    SERIES = %w[return seasons city park parks milestone].freeze

    belongs_to :user
    belongs_to :selection, optional: true
    belongs_to :city_selection, optional: true
    has_many :events, class_name: 'Achievements::CollectibleEvent', dependent: :delete_all

    validates :series, inclusion: { in: SERIES }
    validates :subject_key, presence: true, uniqueness: { scope: %i[user_id series] }

    scope :visible, -> { where(revoked_at: nil) }

    def unlocked?
      level.positive? && revoked_at.nil?
    end

    def privacy_hidden?
      place = selection&.place
      place && Maps::PrivacyZoneMasker.new(user).in_zone?(place.lon, place.lat)
    end

    def geographic?
      %w[park parks milestone].include?(series)
    end

    def publishable?
      return false if privacy_hidden?

      if geographic?
        return false unless data['public'].is_a?(Hash) && data['privacy_fingerprint'] == PrivacyFingerprint.call(user)

        return series != 'park' || data.dig('public', 'progress').to_f.positive?
      end

      selection.present? || city_selection.present?
    end
  end
end
