# frozen_string_literal: true

class Exploration::State < ApplicationRecord
  self.table_name = 'exploration_states'

  # Live tracking dirties the state continuously; a full-history rebuild runs at
  # most this often unless the dataset changes or nothing is published yet.
  REFRESH_INTERVAL = 1.hour

  scope :activated, -> { where.not(activated_at: nil) }

  def settled?(snapshot)
    return false unless failed_at.nil? && snapshot && snapshot.dataset_id == Exploration::Geography.current&.id &&
                        !snapshot.world_opened_area.nil?

    revision == published_revision || snapshot.completed_at&.>(REFRESH_INTERVAL.ago)
  end
end
