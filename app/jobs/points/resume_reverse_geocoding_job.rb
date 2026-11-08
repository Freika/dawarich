# frozen_string_literal: true

# Picks the reverse geocoding backlog back up when a provider's over-limit
# cooldown (Geocoding::Cooldown) ends, instead of leaving it for the next
# nightly run.
#
# While a cooldown runs, queued lookups are skipped without a request. When it
# ends, this job geocodes points until the provider itself answers one, then
# queues the backlog one batch per run. Each next run sits behind its batch in
# the queue, so it sees a cooldown that batch started and stops there. If the
# provider refuses again, the next, longer cooldown schedules another attempt,
# so a limit that holds for hours costs one request per attempt instead of a
# queue of skipped jobs each time.
#
# A forced re-run covers points that are already geocoded, which the backlog
# scan cannot see. A forced lookup skipped during a cooldown leaves its point
# alone and lowers a per-user cursor in Redis instead, and once the backlog is
# queued this job walks each cursor forward in the same capped batches. The walk
# takes only points last geocoded before the run's first skip, because anything
# newer was answered by the original queue. With no backlog to probe on, the
# probe is the walk's first forced lookup, and an answer takes that point out of
# the walk the same way.
class Points::ResumeReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  CLAIM_KEY = 'geocoding:resume'
  BATCH_SIZE = 1_000
  # Cached answers say nothing about the provider. Past this many without a
  # real answer, the backlog is queued anyway: a refusal starts a new cooldown
  # and the next run stops there.
  PROBE_LIMIT = 10
  FORCED_RUNS_KEY = 'geocoding:resume:forced_runs'
  FORCED_RUN_STARTS_KEY = 'geocoding:resume:forced_run_starts'
  # Only an answer from the provider renews this, so a provider that never lifts
  # its refusal ends the run instead of retrying it for good.
  FORCED_RUN_TTL = 7.days
  # Compare-and-set: a forced lookup skipped since the cursor was read has
  # lowered it, and that lower position must win. An empty ARGV[3] ends the run.
  ADVANCE_FORCED_RUN_SCRIPT = <<~LUA
    if redis.call('ZSCORE', KEYS[1], ARGV[1]) ~= ARGV[2] then return 0 end
    if ARGV[3] == '' then
      redis.call('ZREM', KEYS[1], ARGV[1])
      redis.call('HDEL', KEYS[2], ARGV[1])
    else
      redis.call('ZADD', KEYS[1], ARGV[3], ARGV[1])
    end
    return 1
  LUA

  # Every lookup skipped during a cooldown asks for a resume; the claim keeps
  # that to one scheduled job until it runs, however long it queues behind the
  # backlog. It still expires, so a job lost from the queue cannot block resumes
  # for good.
  def self.schedule(config)
    wait = Geocoding::Cooldown.remaining(config)
    return if wait.nil?
    return unless claim

    set(wait: wait + Geocoding::Cooldown::RETRY_MARGIN).perform_later
  rescue StandardError => e
    Rails.logger.warn("[Points::ResumeReverseGeocodingJob] Could not schedule a resume: #{e.message}")
  end

  def self.claim
    Sidekiq.redis { |redis| redis.call('SET', CLAIM_KEY, '1', 'NX', 'EX', Geocoding::Cooldown::STRIKES_TTL.to_i) }
  end

  # Fails open like Geocoding::Cooldown: losing the intent costs a re-run, while
  # raising here would break the lookup that was being skipped. The transaction
  # keeps a run that ends in between from leaving a start time behind for the
  # next one.
  def self.remember_forced_run(user_id, point_id)
    Sidekiq.redis do |redis|
      redis.multi do |transaction|
        transaction.call('ZADD', FORCED_RUNS_KEY, 'LT', point_id, user_id)
        transaction.call('HSETNX', FORCED_RUN_STARTS_KEY, user_id, Time.current.to_f)
        expire_forced_runs(transaction, 'NX')
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[Points::ResumeReverseGeocodingJob] Could not remember a forced run: #{e.message}")
  end

  # Called for every lookup the provider answers, so a run stays alive while it
  # waits behind a backlog. Fails open for the same reason as above.
  def self.renew_forced_runs
    Sidekiq.redis { |redis| redis.pipelined { |pipe| expire_forced_runs(pipe) } }
  rescue StandardError => e
    Rails.logger.warn("[Points::ResumeReverseGeocodingJob] Could not renew forced runs: #{e.message}")
  end

  def self.expire_forced_runs(client, *options)
    [FORCED_RUNS_KEY, FORCED_RUN_STARTS_KEY].each { |key| client.call('EXPIRE', key, FORCED_RUN_TTL.to_i, *options) }
  end
  private_class_method :expire_forced_runs

  def perform(after_id = nil)
    Sidekiq.redis { |redis| redis.call('DEL', CLAIM_KEY) }

    config = Geocoding::Config.resolved_config
    return unless config.enabled?

    probe_provider(config) unless after_id || Geocoding::Cooldown.active?(config)
    # A refused probe starts the next cooldown; try again when it ends.
    return self.class.schedule(config) if Geocoding::Cooldown.active?(config)

    queue_next_batch(config, after_id || 0)
  end

  private

  def probe_provider(config)
    point_ids = backlog.order(:id).limit(PROBE_LIMIT).pluck(:id)
    forced = point_ids.empty?
    point_ids = forced_probe_ids(config) if forced

    point_ids.each do |point_id|
      ReverseGeocoding::Points::FetchData.new(point_id, force: forced).call
      break if Geocoding::Cooldown.active?(config) || !Geocoding::Cooldown.unanswered_refusal?(config)
    end
  end

  def forced_probe_ids(config)
    run = next_forced_run(config)
    run ? forced_points(*run).limit(PROBE_LIMIT).pluck(:id) : []
  end

  def queue_next_batch(config, after_id)
    rows = backlog.where('id > ?', after_id).order(:id).limit(BATCH_SIZE).pluck(:id, :user_id)

    queue_lookups(rows.map(&:first))
    rows.map(&:last).uniq.each { |user_id| Cache::InvalidateUserCaches.new(user_id).call }

    if rows.size == BATCH_SIZE
      self.class.perform_later(rows.last.first) if self.class.claim
    else
      queue_forced_batch(config, rows.last&.first || after_id, BATCH_SIZE - rows.size)
    end
  end

  # One user per run, so the batch cap holds however many runs are waiting.
  def queue_forced_batch(config, after_id, limit)
    user_id, cursor, first_skip_at = next_forced_run(config)
    return if user_id.nil?

    ids = forced_points(user_id, cursor, first_skip_at).limit(limit).pluck(:id)
    # Moved before queueing: a job from this batch that is skipped straight away
    # has to find the cursor already past it, or its lower position is lost.
    advance_forced_run(user_id, cursor, ids.size == limit ? ids.last + 1 : nil)

    begin
      ActiveJob.perform_all_later(ids.map { |id| ReverseGeocodingJob.new('Point', id, force: true) })
    rescue StandardError
      self.class.remember_forced_run(user_id, cursor)
      raise
    end

    self.class.perform_later(after_id) if forced_runs? && self.class.claim
  end

  def next_forced_run(config)
    # Hosted instances refuse a forced re-run on a paid provider, so a provider
    # switched while these runs waited must not slip past that refusal.
    if config.paid_provider? && !DawarichSettings.self_hosted?
      Sidekiq.redis { |redis| redis.call('DEL', FORCED_RUNS_KEY, FORCED_RUN_STARTS_KEY) }
      return
    end

    Sidekiq.redis do |redis|
      member, score = redis.call('ZRANGE', FORCED_RUNS_KEY, 0, 0, 'WITHSCORES').first
      next unless member

      # A missing start time widens the walk rather than dropping the run.
      first_skip_at = redis.call('HGET', FORCED_RUN_STARTS_KEY, member) || Time.current
      [member.to_i, score.to_i, Time.zone.at(first_skip_at.to_f)]
    end
  end

  # Not-yet-geocoded points never match: the backlog already covers them.
  def forced_points(user_id, cursor, first_skip_at)
    Point.where(user_id: user_id).complete
         .where('id >= ? AND reverse_geocoded_at < ?', cursor, first_skip_at).order(:id)
  end

  def advance_forced_run(user_id, cursor, next_cursor)
    Sidekiq.redis do |redis|
      redis.call('EVAL', ADVANCE_FORCED_RUN_SCRIPT, 2, FORCED_RUNS_KEY, FORCED_RUN_STARTS_KEY,
                 user_id, cursor, next_cursor.to_s)
    end
  end

  def forced_runs?
    Sidekiq.redis { |redis| redis.call('ZCARD', FORCED_RUNS_KEY) }.positive?
  end

  def queue_lookups(point_ids)
    claimed = Point.claim_geocode_ids(point_ids)
    return if claimed.empty?

    begin
      ActiveJob.perform_all_later(claimed.map { |id| ReverseGeocodingJob.new('Point', id, force: false) })
    rescue StandardError
      claimed.each { |id| ReverseGeocodingJob.release_geocode_claim('Point', id) }
      raise
    end
  end

  def backlog
    Point.not_reverse_geocoded.complete
  end
end
