# frozen_string_literal: true

class AnalyticsEvent < ApplicationRecord
  belongs_to :user

  enum :event, { import_succeeded: 0, first_map_data_viewed: 1 }, prefix: :event

  # Inserts the event unless its dedup_key was already recorded, and returns
  # it, or nil for a duplicate. ON CONFLICT keeps a concurrent duplicate from
  # raising, which would abort the surrounding transaction.
  def self.record(user:, event:, dedup_key:, properties: {})
    result = insert_all(
      [{ user_id: user.id, event: events.fetch(event.to_s), dedup_key:, properties: }],
      unique_by: :dedup_key, returning: [:id]
    )
    find(result.rows.first.first) if result.rows.any?
  end
end
