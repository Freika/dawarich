# frozen_string_literal: true

class Tracks::BackfillState
  MERGE = <<~SQL.squish
    INSERT INTO phoenix.track_backfill_ranges AS stored
      (user_id, earliest_timestamp, latest_timestamp, cycle_id, time_zone, due_at, expires_at, inserted_at, updated_at)
    VALUES (?, ?, ?, ?::uuid, ?, ?, ?, ?, ?)
    ON CONFLICT (user_id) DO UPDATE SET
      earliest_timestamp = CASE WHEN stored.expires_at <= EXCLUDED.updated_at THEN EXCLUDED.earliest_timestamp
        ELSE LEAST(stored.earliest_timestamp, EXCLUDED.earliest_timestamp) END,
      latest_timestamp = CASE WHEN stored.expires_at <= EXCLUDED.updated_at THEN EXCLUDED.latest_timestamp
        ELSE GREATEST(stored.latest_timestamp, EXCLUDED.latest_timestamp) END,
      cycle_id = CASE WHEN stored.expires_at <= EXCLUDED.updated_at OR NOT stored.scheduled
        THEN EXCLUDED.cycle_id ELSE stored.cycle_id END,
      time_zone = CASE WHEN stored.expires_at <= EXCLUDED.updated_at THEN EXCLUDED.time_zone ELSE stored.time_zone END,
      due_at = CASE WHEN stored.expires_at <= EXCLUDED.updated_at OR NOT stored.scheduled
        THEN EXCLUDED.due_at ELSE stored.due_at END,
      expires_at = EXCLUDED.expires_at, scheduled = true,
      inserted_at = CASE WHEN stored.expires_at <= EXCLUDED.updated_at THEN EXCLUDED.inserted_at ELSE stored.inserted_at END,
      updated_at = EXCLUDED.updated_at
    RETURNING *
  SQL
  REMOVE_LEGACY = <<~LUA
    local current = redis.call('ZRANGE', KEYS[1], 0, -1)
    if #current ~= #ARGV then return 0 end
    for i = 1, #ARGV do if current[i] ~= ARGV[i] then return 0 end end
    return redis.call('DEL', KEYS[1], KEYS[2])
  LUA

  def initialize(user_id, timestamps)
    @user_id = user_id
    @timestamps = timestamps.compact
  end

  def call
    return Tracks::BackfillScheduler.new(@user_id, @timestamps).call unless self.class.table?
    return if @timestamps.empty?

    legacy = Sidekiq.redis { _1.zrange(range_key, 0, -1) }
    values = @timestamps + legacy.map(&:to_i)
    now = Time.current
    return if values.min >= now.to_i - 6.hours.to_i

    ActiveRecord::Base.transaction do
      owner = JobOwnership.lock_owner('command:tracks.backfill')
      cycle = SecureRandom.uuid
      range = self.class.accumulate(@user_id, values, cycle, now)
      publish(range, owner) if range.fetch('cycle_id') == cycle
      remove_legacy_after_commit(legacy) if legacy.present?
    end
  end

  def self.table? = PhoenixSchema.table?('track_backfill_ranges')

  def self.accumulate(user_id, values, cycle, now)
    binds = [user_id, values.min, values.max, cycle, Time.zone.name, now + 1.minute, now + 6.hours, now, now]
    connection.select_one(ActiveRecord::Base.sanitize_sql_array([MERGE, *binds]))
  end

  def self.pop_range(user_id)
    return Tracks::BackfillScheduler.pop_range(user_id) unless table?

    new(user_id, []).send(:consume)
  end

  def self.connection = ActiveRecord::Base.connection

  private

  def range_key = "track_backfill_range:user:#{@user_id}"
  def schedule_key = "track_backfill:user:#{@user_id}"

  def consume
    snapshot = Sidekiq.redis { _1.zrange(range_key, 0, -1) }
    now = Time.current
    ActiveRecord::Base.transaction do
      self.class.accumulate(@user_id, snapshot.map(&:to_i), SecureRandom.uuid, now) if snapshot.present?
      row = self.class.connection.select_one(ActiveRecord::Base.sanitize_sql_array(
                                               ['DELETE FROM phoenix.track_backfill_ranges WHERE user_id = ? ' \
                                                'RETURNING *', @user_id]
                                             ))
      remove_legacy_after_commit(snapshot) if snapshot.present?
      row.values_at('earliest_timestamp', 'latest_timestamp') if row && row.fetch('expires_at') > now
    end
  end

  def publish(range, owner)
    payload = range.slice('user_id', 'cycle_id', 'time_zone')
    if owner == :oban
      JobCommands.forward('tracks.backfill', payload, event_id: range.fetch('cycle_id'), aggregate_id: @user_id,
                                                     producer: self.class.name, scheduled_at: range.fetch('due_at'))
    else
      ActiveRecord.after_all_transactions_commit do
        job = Time.use_zone(range.fetch('time_zone')) do
          Tracks::BackfillGenerationJob.set(wait_until: range.fetch('due_at')).perform_later(@user_id)
        end
        raise IOError, 'backfill enqueue aborted' unless job
      rescue StandardError
        sql = 'UPDATE phoenix.track_backfill_ranges SET scheduled = false WHERE user_id = ? AND cycle_id = ?::uuid'
        self.class.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, @user_id, range.fetch('cycle_id')]))
        raise
      end
    end
  end

  def remove_legacy_after_commit(snapshot)
    ActiveRecord.after_all_transactions_commit do
      Sidekiq.redis { _1.call('EVAL', REMOVE_LEGACY, 2, range_key, schedule_key, *snapshot) }
    rescue RedisClient::Error
      nil
    end
  end
end
