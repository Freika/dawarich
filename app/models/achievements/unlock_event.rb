# frozen_string_literal: true

module Achievements
  class UnlockEvent < ApplicationRecord
    self.table_name = 'achievement_unlock_events'

    KINDS = %w[geography set].freeze

    belongs_to :user

    scope :pending, -> { where(seen_at: nil) }

    validates :kind, inclusion: { in: KINDS }
    validates :key, presence: true, uniqueness: { scope: %i[user_id kind] }

    # One insert for a bulk import, with a unique index making retries harmless.
    # Historic awards are not backfilled: only newly earned cards should pop up.
    def self.enqueue_geographies!(user_id:, codes:)
      visible = codes.select do |code|
        code.match?(/\A[A-Z]{2}\z/) ? Registry.find("country_#{code.downcase}") : Registry.subdivision_parent_for(code)
      end
      return if visible.empty?

      now = Time.current
      rows = visible.map do |code|
        { user_id: user_id, kind: 'geography', key: code, created_at: now, updated_at: now }
      end
      insert_all(rows, unique_by: 'index_achievement_unlock_events_on_user_kind_key')
    end

    def self.enqueue_set!(user_id:, definition:)
      return if definition.kind == 'region_set' || definition.flat?

      create_or_find_by!(user_id: user_id, kind: 'set', key: definition.key)
    end
  end
end
