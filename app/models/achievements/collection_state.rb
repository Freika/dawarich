# frozen_string_literal: true

module Achievements
  class CollectionState < ApplicationRecord
    self.table_name = 'achievement_collection_states'

    belongs_to :user

    def current?
      completed_at.present? && revision == published_revision &&
        published_dataset_id == Exploration::Geography.current&.id &&
        timezone_version == LocationTimezone.version &&
        privacy_fingerprint == PrivacyFingerprint.call(user)
    end
  end
end
