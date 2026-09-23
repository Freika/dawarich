# frozen_string_literal: true

module Tracks
  module MapMatching
    class Enqueuer
      STALE_CLAIM_AFTER = 1.hour

      def self.call(track)
        new(track).call
      rescue StandardError => e
        track_id = track&.id
        ExceptionReporter.call(e, "Failed to prepare map matching for track #{track_id}")
        false
      end

      def initialize(track)
        @track = track
      end

      def call
        return false unless enabled?
        return false unless track&.persisted?
        return false if track.demo?

        input = ::MapMatching::Input.new(track)
        digest = ::MapMatching::Fingerprint.call(input)
        return publish_skipped(digest, input) unless input.eligible?
        return false unless claim(digest)

        enqueue(digest)
        true
      end

      private

      attr_reader :track

      def enabled?
        DawarichSettings.map_matching_enabled? && DawarichSettings.atlas_url.present?
      end

      def claim(digest)
        claimed = false
        track.with_lock do
          track.reload
          next if current_result?(digest)
          next if live_claim?(digest)

          track.write_map_matching!(
            {
              map_matching_status: :pending,
              map_matching_input_digest: digest,
              map_matching_data: { claimed_at: Time.current.iso8601 },
              map_matched_at: nil
            }
          )
          claimed = true
        end
        claimed
      end

      def live_claim?(digest)
        return false unless track.map_matching_status_pending? && track.map_matching_input_digest == digest

        claimed_at = Time.zone.parse(track.map_matching_data['claimed_at'].to_s)
        claimed_at.present? && claimed_at > STALE_CLAIM_AFTER.ago
      end

      def current_result?(digest)
        track.map_matching_input_digest == digest && track.map_matching_result?
      end

      def enqueue(digest)
        Tracks::MapMatchJob.perform_later(track.id, digest)
      rescue StandardError => e
        Tracks::MapMatchJob.publish_failure(track.id, digest, e, attempt: 0)
        ExceptionReporter.call(e, "Failed to enqueue map matching for track #{track.id}")
        false
      end

      def publish_skipped(digest, input)
        return false if track.map_matching_status_skipped? && track.map_matching_input_digest == digest

        result = ::MapMatching::Processor.skipped(input)
        track.write_map_matching!(
          {
            matched_path: nil,
            map_matching_status: result.status,
            map_matching_input_digest: digest,
            map_matching_data: result.data,
            map_matched_at: Time.current
          }
        )
        false
      end
    end
  end
end
