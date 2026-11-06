# frozen_string_literal: true

# Picks the reverse geocoding backlog back up when a provider's over-limit
# cooldown (Geocoding::Cooldown) ends, instead of leaving it for the next
# nightly run.
#
# While a cooldown runs, queued lookups are skipped without a request. When it
# ends, this job geocodes one point first and queues the rest only if the
# provider answers. If the provider refuses again, the next, longer cooldown
# schedules another attempt, so a limit that holds for hours costs one request
# per attempt instead of a queue of skipped jobs each time.
class Points::ResumeReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  CLAIM_KEY = 'geocoding:resume'
  # Runs the job just after the cooldown key has expired.
  MARGIN = 2.seconds

  # Every lookup skipped during a cooldown asks for a resume; the claim keeps
  # that to one scheduled job. It outlives the job's run time by a minute, so a
  # job lost from the schedule cannot block the next one for longer.
  def self.schedule(config)
    wait = Geocoding::Cooldown.remaining(config)
    return if wait.nil?

    claimed = Sidekiq.redis do |redis|
      redis.call('SET', CLAIM_KEY, '1', 'NX', 'EX', wait + MARGIN.to_i + 60)
    end
    return unless claimed

    set(wait: wait + MARGIN).perform_later
  rescue StandardError => e
    Rails.logger.warn("[Points::ResumeReverseGeocodingJob] Could not schedule a resume: #{e.message}")
  end

  def perform
    Sidekiq.redis { |redis| redis.call('DEL', CLAIM_KEY) }

    config = Geocoding::Config.resolved_config
    return unless config.enabled?
    return self.class.schedule(config) if Geocoding::Cooldown.active?(config)

    probe = Point.not_reverse_geocoded.complete.order(:id).first
    return if probe.nil?

    ReverseGeocoding::Points::FetchData.new(probe.id).call
    # A refused probe starts the next cooldown; try again when it ends.
    return self.class.schedule(config) if Geocoding::Cooldown.active?(config)

    Points::NightlyReverseGeocodingJob.perform_now
  end
end
