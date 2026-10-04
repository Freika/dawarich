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

  def self.for_execution(user_id, cycle_id: nil, time_zone: nil)
    new(user_id, []).send(:execution_range, cycle_id, time_zone)
  end

  def self.rearm(range)
    new(range.fetch('user_id'), []).send(:rearm_cycle, range)
  end

  private

  def range_key = "track_backfill_range:user:#{@user_id}"
  def schedule_key = "track_backfill:user:#{@user_id}"

  def rearm_cycle(failed)
    ActiveRecord::Base.transaction do
      owner = JobOwnership.lock_owner('command:tracks.backfill')
      statement = 'SELECT * FROM phoenix.track_backfill_ranges WHERE user_id = ? FOR UPDATE'
      current = self.class.connection.select_one(ActiveRecord::Base.sanitize_sql_array([statement, @user_id]))
      if current && current.fetch('cycle_id') == failed.fetch('cycle_id')
        statement = 'UPDATE phoenix.track_backfill_ranges SET due_at = ?, scheduled = true, ' \
                    'expires_at = GREATEST(expires_at, ?), updated_at = ? ' \
                    'WHERE user_id = ? AND cycle_id = ?::uuid RETURNING *'
        row = self.class.connection.select_one(ActiveRecord::Base.sanitize_sql_array(
                                                 [statement, Time.current + 1.minute, Time.current + 6.hours,
                                                  Time.current, @user_id, failed.fetch('cycle_id')]
                                               ))
        publish(row, owner)
      else
        Time.use_zone(failed.fetch('time_zone')) do
          self.class.new(@user_id, failed.values_at('earliest_timestamp', 'latest_timestamp')).call
        end
      end
    end
  end

  def execution_range(cycle_id, time_zone)
    if cycle_id.nil?
      snapshot = Sidekiq.redis { _1.zrange(range_key, 0, -1) }
      if snapshot.present?
        Time.use_zone(time_zone || Time.zone.name) do
          self.class.accumulate(@user_id, snapshot.map(&:to_i), SecureRandom.uuid, Time.current)
        end
        remove_legacy_after_commit(snapshot)
      end
    end
    statement = 'SELECT * FROM phoenix.track_backfill_ranges WHERE user_id = ?'
    binds = [@user_id]
    if cycle_id
      statement += ' AND cycle_id = ?::uuid'
      binds << cycle_id
    end
    row = self.class.connection.select_one(ActiveRecord::Base.sanitize_sql_array(["#{statement} FOR UPDATE", *binds]))
    row if row && row.fetch('expires_at') > Time.current
  end

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
          Tracks::BackfillGenerationJob.set(wait_until: range.fetch('due_at')).perform_later(
            @user_id, cycle_id: range.fetch('cycle_id'), time_zone: range.fetch('time_zone')
          )
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
