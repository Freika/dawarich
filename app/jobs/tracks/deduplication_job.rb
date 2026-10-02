# frozen_string_literal: true

# Background job to deduplicate tracks for a single user.
# Enqueued by the DeduplicateTracks migration.
class Tracks::DeduplicationJob < ApplicationJob
  queue_as :tracks

  def perform(user_id)
    return if ReleaseCommands.forwarded?(self, 'release.tracks_dedup', { 'user_id' => user_id }, aggregate_id: user_id)

    user = find_user_or_skip(user_id) || return

    Tracks::Deduplicator.new(user).call
  end
end
