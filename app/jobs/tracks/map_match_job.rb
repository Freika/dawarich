# frozen_string_literal: true

class Tracks::MapMatchJob < ApplicationJob
  MAX_ATTEMPTS = 5

  queue_as :map_matching
  sidekiq_options retry: false

  retry_on ::MapMatching::Atlas::Client::RetryableError,
           wait: :polynomially_longer,
           attempts: MAX_ATTEMPTS do |job, error|
    track_id, digest = job.arguments
    Tracks::MapMatchJob.publish_failure(track_id, digest, error, attempt: job.executions)
  end

  def perform(track_id, digest)
    return unless enabled?

    track = Track.find_by(id: track_id)
    return unless current?(track, digest)

    input = ::MapMatching::Input.new(track)
    return unless ::MapMatching::Fingerprint.call(input) == digest

    result = ::MapMatching::Processor.new(input).call
    publish(track, digest, result)
  rescue ::MapMatching::Atlas::Client::RateLimited => e
    if executions < MAX_ATTEMPTS
      retry_job(wait: e.retry_after.presence || polynomial_wait)
    else
      self.class.publish_failure(track_id, digest, e, attempt: executions)
    end
  rescue ::MapMatching::Atlas::Client::Error => e
    raise if e.transient?

    self.class.publish_failure(track_id, digest, e, attempt: executions)
  end

  def self.publish_failure(track_id, digest, error, attempt:)
    track = Track.find_by(id: track_id)
    return unless track

    track.with_lock do
      track.reload
      next unless track.map_matching_status_pending?
      next unless track.map_matching_input_digest == digest

      code = error.respond_to?(:code) ? error.code : 'enqueue_failed'
      status = error.respond_to?(:status) ? error.status : nil
      track.update!(
        matched_path: nil,
        map_matching_status: :failed,
        map_matching_data: {
          schema_version: ::MapMatching::Processor::SCHEMA_VERSION,
          policy_version: ::MapMatching::QualityPolicy::VERSION,
          provider: { name: 'atlas' },
          segments: [],
          error: { code:, status:, attempt:, message: code }.compact
        },
        map_matched_at: Time.current
      )
      Rails.logger.warn(
        "event=map_matching.failed track_id=#{track.id} digest=#{digest.first(12)} " \
        "code=#{code} status=#{status} attempt=#{attempt}"
      )
    end
  end

  private

  def enabled?
    DawarichSettings.map_matching_enabled? && DawarichSettings.atlas_url.present?
  end

  def current?(track, digest)
    track&.map_matching_status_pending? && track.map_matching_input_digest == digest
  end

  def polynomial_wait
    (executions**4) + 2
  end

  def publish(track, digest, result)
    track.with_lock do
      track.reload
      return unless current?(track, digest)

      track.update!(
        matched_path: result.path,
        map_matching_status: result.status,
        map_matching_data: result.data,
        map_matched_at: Time.current
      )
      Rails.logger.info(
        "event=map_matching.completed track_id=#{track.id} digest=#{digest.first(12)} " \
        "status=#{result.status}"
      )
    end
  end
end
