# frozen_string_literal: true

module Tracks
  class TransportationModeRecalculationJob < ApplicationJob
    queue_as :tracks
    sidekiq_options retry: 1

    def perform(user_id)
      @user = find_user_or_skip(user_id) || return

      @status = TransportationRecalculationStatus.new(user_id)
      reprocess_all_tracks
    rescue StandardError => e
      Rails.logger.error "TransportationModeRecalculationJob failed for user #{user_id}: #{e.message}"
      @status&.fail(e.message)
      raise
    end

    private

    def reprocess_all_tracks
      total = @user.tracks.count
      @status.start(total_tracks: total)

      processed = 0
      @user.tracks.find_each do |track|
        Tracks::Reprocessor.reprocess(track)
        processed += 1

        # Update progress periodically (every 10 tracks)
        @status.update_progress(processed_tracks: processed, total_tracks: total) if (processed % 10).zero?
      end

      @status.update_progress(processed_tracks: processed, total_tracks: total)
      @status.complete
      Rails.logger.info "Reprocessed #{processed} tracks for user #{@user.id}"
    end
  end
end
