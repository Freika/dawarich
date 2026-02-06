# frozen_string_literal: true

# Background job to deduplicate tracks for a single user.
# Enqueued by the DeduplicateTracksAndAddUniqueIndex migration.
class Tracks::DeduplicationJob < ApplicationJob
  queue_as :tracks

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    Tracks::Deduplicator.new(user).call
  end
end
