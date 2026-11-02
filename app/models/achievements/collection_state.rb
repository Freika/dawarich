# frozen_string_literal: true

module Achievements
  class CollectionState < ApplicationRecord
    self.table_name = 'achievement_collection_states'

    belongs_to :user

    def current?
      shareable? && revision == published_revision
    end

    # Published cards follow the current boundaries, timezone rules and privacy zones.
    # They may lag new points by up to Exploration::State::REFRESH_INTERVAL.
    def shareable?
      completed_at.present? &&
        published_dataset_id == Exploration::Geography.current&.id &&
        timezone_version == LocationTimezone.version &&
        privacy_fingerprint == PrivacyFingerprint.call(user)
    end

    def settled?
      shareable? && failed_at.nil? &&
        (revision == published_revision || completed_at > Exploration::State::REFRESH_INTERVAL.ago)
    end
  end
end
