# frozen_string_literal: true

class Places::OrphanCleanupJob < ApplicationJob
  queue_as :places
  BATCH = 500

  # Drains the given user's orphan suggested places. Every place carries a
  # user_id (NOT NULL since 20260815100001), so there is no ownerless pass.
  def perform(user_id)
    return unless User.exists?(id: user_id)

    total = 0
    loop do
      deleted = delete_batch(user_id)
      break if deleted.zero?

      total += deleted
      Rails.logger.info("[OrphanCleanup] user=#{user_id} batch=#{deleted} total=#{total}")
      sleep 0.05
    end
  end

  private

  def delete_batch(user_id)
    Place.transaction do
      victim_ids = Place.orphaned.where(user_id: user_id).limit(BATCH).pluck(:id)
      victim_ids.empty? ? 0 : Place.delete_orphans(victim_ids)
    end
  end
end
