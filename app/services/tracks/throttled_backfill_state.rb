# frozen_string_literal: true

class Tracks::ThrottledBackfillState
  TYPE = 'tracks.throttled_backfill'
  OWNER_KEY = "command:#{TYPE}".freeze
  SNAPSHOT = <<~LUA
    local value = redis.call('GET', KEYS[1])
    if not value then return {} end
    return {value, redis.call('PTTL', KEYS[1]), redis.call('PEXPIRETIME', KEYS[1])}
  LUA
  REMOVE = <<~LUA
    if redis.call('GET', KEYS[1]) ~= ARGV[1] then return 0 end
    if redis.call('PEXPIRETIME', KEYS[1]) ~= tonumber(ARGV[2]) then return 0 end
    return redis.call('DEL', KEYS[1])
  LUA
  UPSERT = <<~SQL.squish
    INSERT INTO phoenix.track_backfill_walks AS stored
      (user_id, walk_id, cursor_timestamp, state, expires_at, time_zone, inserted_at, updated_at, legacy_cursor_pending)
    VALUES (?, ?::uuid, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (user_id) DO UPDATE SET walk_id = EXCLUDED.walk_id,
      cursor_timestamp = EXCLUDED.cursor_timestamp, step_event_id = NULL, selected_start_timestamp = NULL,
      selected_end_timestamp = NULL, state = EXCLUDED.state, expires_at = EXCLUDED.expires_at,
      time_zone = EXCLUDED.time_zone, inserted_at = EXCLUDED.inserted_at, updated_at = EXCLUDED.updated_at,
      legacy_cursor_pending = EXCLUDED.legacy_cursor_pending
    WHERE ? AND stored.expires_at <= EXCLUDED.updated_at
    RETURNING *
  SQL

  def self.table? = PhoenixSchema.table?('track_backfill_walks')
  def self.connection = ActiveRecord::Base.connection
  def self.schedule(user) = new(user.id).schedule

  def self.upsert(id, cursor, state, expires_at, zone, reclaim:)
    now = Time.current
    binds = [id, SecureRandom.uuid, cursor, state, expires_at, zone, now, now, state == 'backoff', reclaim]
    connection.select_one(ActiveRecord::Base.sanitize_sql_array([UPSERT, *binds]))
  end

  def initialize(user_id, cursor = nil, walk_id: nil, time_zone: nil, event_id: nil)
    @user_id = user_id
    @cursor = cursor
    @walk_id = walk_id
    @zone = time_zone || Time.zone.name
    @legacy_event_id = event_id if walk_id.nil?
  end

  def schedule
    legacy = snapshot
    ActiveRecord::Base.transaction do
      owner = JobOwnership.lock_owner(OWNER_KEY)
      state = legacy.present? ? 'backoff' : 'walking'
      walk = adopt(legacy, state, reclaim: true)
      if legacy.present?
        remove_after_commit(legacy)
        false
      elsif walk
        publish(walk, owner, Time.current, walk.fetch('walk_id'))
        true
      else
        false
      end
    end
  end

  def run
    legacy = snapshot
    select_step(legacy)
    start_step
  end

  def forward(event_id)
    legacy = snapshot
    adopt(legacy, 'walking', reclaim: false) unless @walk_id
    adopt_cursor unless @walk_id
    walk = current
    remove_after_commit(legacy) if legacy.present?
    return unless walk

    JobCommands.forward(TYPE, walk.slice('user_id', 'walk_id', 'cursor_timestamp', 'time_zone'),
                        event_id:, aggregate_id: @user_id, producer: self.class.name)
  end

  private

  def redis_key = Tracks::ThrottledBackfillJob.redis_key(@user_id)
  def connection = self.class.connection
  def sql(statement, *binds) = ActiveRecord::Base.sanitize_sql_array([statement, *binds])
  def snapshot = Sidekiq.redis { _1.call('EVAL', SNAPSHOT, 1, redis_key) }

  def adopt(legacy, state, reclaim:)
    ttl = legacy.present? && legacy[1].positive? ? legacy[1] / 1000.0 : 12.hours.to_i
    expires_at = Time.current + ttl
    walk = self.class.upsert(@user_id, @cursor, state, expires_at, @zone, reclaim:)
    if legacy.present? && !walk
      connection.execute(sql('UPDATE phoenix.track_backfill_walks SET expires_at = GREATEST(expires_at, ?), ' \
                             'updated_at = ? WHERE user_id = ?', expires_at, Time.current, @user_id))
    end
    walk
  end

  def select_step(legacy)
    ActiveRecord::Base.transaction do
      JobOwnership.lock_owner(OWNER_KEY)
      adopt(legacy, 'walking', reclaim: false) unless @walk_id
      adopt_cursor unless @walk_id
      walk = current(walking: false)
      remove_after_commit(legacy) if legacy.present?
      return unless walk

      @walk_id = walk.fetch('walk_id')
      user = User.find_by(id: @user_id)
      unless user
        mark_legacy_event
        return release
      end
      return unless walk.fetch('state') == 'walking'
      return if walk.fetch('step_event_id')

      maximum = user.points.where(timestamp: ...(@cursor || Time.current.to_i)).maximum(:timestamp)
      if maximum.nil?
        mark_legacy_event
        return finish
      end

      connection.execute(sql('UPDATE phoenix.track_backfill_walks SET step_event_id = ?::uuid, ' \
                             'selected_start_timestamp = ?, selected_end_timestamp = ? ' \
                             'WHERE user_id = ? AND walk_id = ?::uuid', SecureRandom.uuid,
                             maximum - 30.days.to_i, maximum, @user_id, @walk_id))
    end
  end

  def start_step
    ActiveRecord::Base.transaction do
      owner = JobOwnership.lock_owner(OWNER_KEY)
      JobOwnership.lock_owner(Tracks::GenerationCommand::OWNER_KEY)
      walk = current
      return unless walk&.fetch('step_event_id')
      return release unless (user = User.find_by(id: @user_id))
      return unless claim(walk.fetch('step_event_id'))

      mark_legacy_event unless @legacy_event_id == walk.fetch('step_event_id')

      Time.use_zone(walk.fetch('time_zone')) do
        Tracks::ParallelGenerator.new(user, start_at: Time.zone.at(walk.fetch('selected_start_timestamp')),
                                           end_at: Time.zone.at(walk.fetch('selected_end_timestamp')),
                                           mode: :bulk, untracked_only: true, job_queue: :low_priority,
                                           event_id: walk.fetch('step_event_id')).call
      end
      advance(walk, owner)
    end
  end

  def adopt_cursor
    connection.execute(sql('UPDATE phoenix.track_backfill_walks SET cursor_timestamp = ?, state = \'walking\', ' \
                           'legacy_cursor_pending = false WHERE user_id = ? AND legacy_cursor_pending',
                           @cursor, @user_id))
  end

  def current(walking: true)
    statement = 'SELECT * FROM phoenix.track_backfill_walks WHERE user_id = ? ' \
                'AND cursor_timestamp IS NOT DISTINCT FROM ?::bigint'
    statement += ' AND state = \'walking\'' if walking
    binds = [@user_id, @cursor]
    if @walk_id
      statement += ' AND walk_id = ?::uuid'
      binds << @walk_id
    end
    connection.select_one(sql("#{statement} FOR UPDATE", *binds))
  end

  def claim(event_id)
    connection.select_value(sql('INSERT INTO phoenix.processed_commands (event_id, handler, processed_at) ' \
                                'VALUES (?::uuid, ?, ?) ON CONFLICT (event_id) DO NOTHING RETURNING event_id',
                                event_id, TYPE, Time.current))
  end

  def mark_legacy_event
    claim(@legacy_event_id) if @legacy_event_id
  end

  def advance(walk, owner)
    next_walk = connection.select_one(sql('UPDATE phoenix.track_backfill_walks SET cursor_timestamp = ' \
                                         'selected_start_timestamp, step_event_id = NULL, ' \
                                         'selected_start_timestamp = NULL, selected_end_timestamp = NULL, ' \
                                         'expires_at = ?, updated_at = ? WHERE user_id = ? AND walk_id = ?::uuid ' \
                                         'RETURNING *', Time.current + 12.hours, Time.current, @user_id, @walk_id))
    publish(next_walk, owner, Time.current + 1.minute, walk.fetch('step_event_id'))
  end

  def finish
    connection.execute(sql('UPDATE phoenix.track_backfill_walks SET state = \'backoff\', expires_at = ?, ' \
                           'updated_at = ? WHERE user_id = ? AND walk_id = ?::uuid',
                           Time.current + 7.days, Time.current, @user_id, @walk_id))
  end

  def release
    connection.execute(sql('DELETE FROM phoenix.track_backfill_walks WHERE user_id = ? AND walk_id = ?::uuid',
                           @user_id, @walk_id))
  end

  def publish(walk, owner, at, event)
    payload = walk.slice('user_id', 'walk_id', 'cursor_timestamp', 'time_zone')
    if owner == :oban
      JobCommands.forward(TYPE, payload, event_id: event, aggregate_id: @user_id,
                                        producer: self.class.name, scheduled_at: at)
    else
      ActiveRecord.after_all_transactions_commit do
        Time.use_zone(walk.fetch('time_zone')) do
          Tracks::ThrottledBackfillJob.set(wait_until: at).perform_later(@user_id, walk.fetch('cursor_timestamp'),
                                                                         walk_id: walk.fetch('walk_id'),
                                                                         time_zone: walk.fetch('time_zone'))
        end
      end
    end
  end

  def remove_after_commit(legacy)
    ActiveRecord.after_all_transactions_commit do
      Sidekiq.redis { _1.call('EVAL', REMOVE, 1, redis_key, legacy[0], legacy[2]) }
    rescue RedisClient::Error
      nil
    end
  end
end
