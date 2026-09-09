# frozen_string_literal: true

module Stats
  class ToponymsRefresh
    LOCK_ID = Zlib.crc32('stats:toponyms_refresh')
    DISCOVERY_KEY = 'stats:toponyms_reconciliation:missing_cursor'
    TURN_KEY = 'stats:toponyms_reconciliation:turn'
    CURSOR_KEY = 'stats:toponyms_reconciliation:cursor'
    MONTHS_PER_RUN = 10
    RECONCILIATIONS_PER_RUN = 2
    RUN_BUDGET = 30.seconds

    def call
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        locked = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_ID})")
        next unless locked

        begin
          @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RUN_BUDGET
          @remaining = MONTHS_PER_RUN
          @results = {}
          @scheduled_full = Set.new
          discover_missing_month
          first = Sidekiq.redis { |redis| redis.incr(TURN_KEY).odd? }
          if first
            reconcile
            @results.clear
            refresh_pending
          else
            @remaining -= RECONCILIATIONS_PER_RUN
            refresh_pending
            @remaining = RECONCILIATIONS_PER_RUN
            reconcile if within_budget?
          end
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{LOCK_ID})")
        end
      end
    end

    private

    def reconcile
      cursor = Sidekiq.redis { |redis| redis.get(CURSOR_KEY) }.to_i
      rows = Stat.where('id > ?', cursor).order(:id).limit(RECONCILIATIONS_PER_RUN).pluck(:id, :user_id, :year, :month)
      if rows.empty?
        Sidekiq.redis { |redis| redis.set(CURSOR_KEY, 0) }
        return
      end

      rows.each do |id, user_id, year, month|
        break unless within_budget?

        user = User.find_by(id: user_id)
        refresh(user, year, month) if user
        Sidekiq.redis { |redis| redis.set(CURSOR_KEY, id) }
      end
    end

    def discover_missing_month
      raw = Sidekiq.redis { |redis| redis.get(DISCOVERY_KEY) }
      user_id, timestamp = raw ? JSON.parse(raw) : [0, -2_147_483_648]
      user = User.where('id >= ?', user_id).order(:id).first
      return Sidekiq.redis { |redis| redis.del(DISCOVERY_KEY) } unless user

      timestamp = -2_147_483_648 if user.id != user_id
      first = user.points.not_anomaly.where('timestamp >= ?', timestamp).order(:timestamp).pick(:timestamp)
      if first
        date = Time.at(first).in_time_zone(user.timezone_iana).beginning_of_month
        unless user.stats.exists?(year: date.year, month: date.month)
          @remaining -= 1
          schedule_full(user.id, date.year, date.month)
        end
        cursor = [user.id, date.next_month.to_i]
      else
        cursor = [user.id + 1, -2_147_483_648]
      end
      Sidekiq.redis { |redis| redis.set(DISCOVERY_KEY, cursor.to_json) }
    end

    def refresh_pending
      users = {}
      GeocodedDays.due(limit: MONTHS_PER_RUN * 31).each do |member, version|
        break unless time_remaining?

        user_id = member.split(':', 2).first.to_i
        user = users.fetch(user_id) { users[user_id] = User.find_by(id: user_id) }
        unless user
          GeocodedDays.acknowledge(member => version)
          next
        end

        months = GeocodedDays.local_months(member, user)
        needed = months.count { |year, month| !@results.key?([user.id, year, month]) }
        break if needed > @remaining

        success = months.all? { |year, month| refresh(user, year, month, invalidate_cache: true) }
        if success
          GeocodedDays.acknowledge(member => version)
        else
          GeocodedDays.postpone(member)
        end
      end
    end

    def refresh(user, year, month, invalidate_cache: false)
      key = [user.id, year, month]
      return @results[key] if @results.key?(key)

      return false unless within_budget?

      @remaining -= 1
      if RefreshToponyms.new(user, year, month, invalidate_cache: invalidate_cache).call
        @results[key] = true
      else
        schedule_full(user.id, year, month)
        @results[key] = false
      end
    rescue StandardError => e
      Rails.logger.error("Toponym refresh failed for user #{user.id} #{year}-#{month}: #{e.class}: #{e.message}")
      ExceptionReporter.call(e)
      @results[key] = false
    end

    def within_budget?
      @remaining.positive? && time_remaining?
    end

    def time_remaining?
      Process.clock_gettime(Process::CLOCK_MONOTONIC) < @deadline
    end

    def schedule_full(user_id, year, month)
      return unless @scheduled_full.add?([user_id, year, month])

      Stats::CalculatingJob.perform_later(user_id, year, month, notify_on_failure: false)
    end
  end
end
