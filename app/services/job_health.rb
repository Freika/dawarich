# frozen_string_literal: true

module JobHealth
  STALE_SECONDS = 60
  OVERDUE_SECONDS = 300
  REFRESH_SECONDS = 15
  REFRESHER = 'job-health-refresher'
  UNKNOWN = { status: 'unknown', alarm: false }.freeze
  REFRESHER_LOCK = Mutex.new

  module_function

  def summary(now = monotonic)
    start_refresher unless Rails.env.test?
    value, at = @cached
    return UNKNOWN if value.nil? || now - at > STALE_SECONDS

    value
  end

  def refresh!(node = ENV.fetch('DAWARICH_PHOENIX_NODE', nil))
    value = Rails.application.executor.wrap { compute(node) }
    @cached = [value, monotonic]
    value
  end

  def start_refresher(interval: REFRESH_SECONDS)
    REFRESHER_LOCK.synchronize do
      Thread.list.find { |thread| thread.name == REFRESHER } || spawn_refresher(interval)
    end
  rescue StandardError => e
    Rails.logger.warn("[JobHealth] refresher failed to start: #{e.class}")
    nil
  end

  def spawn_refresher(interval)
    thread = Thread.new do
      loop do
        begin
          ::JobHealth.refresh!
        rescue StandardError => e
          Rails.logger.warn("[JobHealth] refresh failed: #{e.class}")
        end
        sleep interval
      end
    end
    thread.name = REFRESHER
    thread
  end

  def reset!
    @cached = nil
  end

  def compute(node)
    flags = read { flags_for(node) if JobOwnership.table? }
    return { status: node.present? ? 'stale' : 'absent', alarm: false } unless flags

    status = if node.blank? then 'absent'
             elsif flags['this_fresh'] then 'ok'
             else 'stale'
             end
    { status:, alarm: (flags['oban_owns'] && !flags['any_fresh']) || flags['overdue'] }
  rescue StandardError => e
    Rails.logger.warn("[JobHealth] summary failed: #{e.class}")
    UNKNOWN
  end

  def flags_for(node)
    connection.select_one(sanitize([FLAGS_SQL, { node: node.to_s, stale: STALE_SECONDS, overdue: OVERDUE_SECONDS }]))
  end

  def gauges(include_drain: false)
    read do
      next { tables: false } unless JobOwnership.table?

      metrics = {
        tables: true,
        outbox: connection.select_one(OUTBOX_SQL),
        owners: connection.select_all(OWNERS_SQL).to_a,
        nodes: connection.select_all(NODES_SQL).to_a,
        oban: oban_counts,
        rails_commands: rails_commands_counts
      }
      metrics[:drain] = drain_counts if include_drain
      metrics
    end
  rescue StandardError => e
    Rails.logger.warn("[JobHealth] gauges failed: #{e.class}")
    { tables: :unknown }
  end

  def drain_counts
    required = %w[phoenix.rails_commands phoenix.rails_commands_dead phoenix.track_generations
                  phoenix.track_generation_chunks phoenix.release_operations]
    return { tables: :unknown } unless required.all? do |table|
      connection.select_value(sanitize(['SELECT to_regclass(?) IS NOT NULL', table]))
    end

    keys = JobCommands::COMMANDS.keys.map { "command:#{_1}" } +
           YAML.load_file(Rails.root.join('config/schedule.yml')).keys.map { "cron:#{_1}" }
    workers = oban_counts.reject { |row| %w[completed cancelled].include?(row['state']) }
    oban = connection.select_value("SELECT to_regclass('oban.oban_jobs') IS NOT NULL")
    sql = if oban
            DRAIN_SQL
          else
            DRAIN_SQL.sub(
              /\(SELECT count\(\*\) FROM oban\.oban_jobs[^\n]+?\)::integer AS incomplete_oban/,
              'NULL::integer AS incomplete_oban'
            )
          end
    {
      tables: true, counts: connection.select_one(sanitize([sql, { keys: }])),
      incomplete_workers: workers,
      legacy_schedulers: if oban
                           LEGACY_SCHEDULERS.map do |key, worker|
                             incomplete = workers.sum { _1['worker'] == worker ? _1['count'] : 0 }
                             { key:, worker:, incomplete: }
                           end
                         end,
      producer_kinds: RailsCommands::Registry::HANDLERS.keys.sort.map { |kind| { kind:, status: 'BLOCKED' } }
    }
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def warn_if_absent(env = ENV)
    return if env['DAWARICH_PHOENIX_NODE'].present?

    Rails.logger.warn('[Phoenix] not running in this container: ' \
                      'jobs owned by Phoenix wait in the outbox until a Phoenix process runs')
  end

  def oban_counts
    return [] unless connection.select_value("SELECT to_regclass('oban.oban_jobs') IS NOT NULL")

    connection.select_all(OBAN_SQL).to_a
  end

  def rails_commands_counts
    return nil unless connection.select_value("SELECT to_regclass('phoenix.rails_commands_dead') IS NOT NULL")

    connection.select_one(RAILS_COMMANDS_SQL)
  end

  def read(&)
    ActiveRecord::Base.transaction do
      connection.execute("SET LOCAL statement_timeout = '500ms'")
      yield
    end
  end

  def connection = ActiveRecord::Base.connection

  def sanitize(args) = ActiveRecord::Base.sanitize_sql_array(args)

  FLAGS_SQL = <<~SQL.squish
    SELECT
      EXISTS (SELECT 1 FROM phoenix.runtime_nodes WHERE node = :node AND beat_at > now() - make_interval(secs => :stale)) AS this_fresh,
      EXISTS (SELECT 1 FROM phoenix.runtime_nodes WHERE beat_at > now() - make_interval(secs => :stale)) AS any_fresh,
      EXISTS (SELECT 1 FROM phoenix.job_owners WHERE owner = 'oban') AS oban_owns,
      EXISTS (SELECT 1 FROM job_outbox WHERE state = 'pending' AND scheduled_at < now() - make_interval(secs => :overdue)) AS overdue
  SQL

  OWNERS_SQL = <<~SQL.squish
    SELECT key, owner, pinned, updated_at, updated_by FROM phoenix.job_owners ORDER BY key
  SQL

  NODES_SQL = <<~SQL.squish
    SELECT node, started_at, beat_at FROM phoenix.runtime_nodes ORDER BY node
  SQL

  OBAN_SQL = <<~SQL.squish
    SELECT worker, state, count(*)::integer AS count FROM oban.oban_jobs GROUP BY worker, state ORDER BY worker, state
  SQL

  RAILS_COMMANDS_SQL = <<~SQL.squish
    SELECT
      (SELECT count(*) FROM phoenix.rails_commands
         WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now()))::integer AS due,
      (SELECT count(*) FROM phoenix.rails_commands WHERE leased_until >= now())::integer AS leased,
      (SELECT count(*) FROM phoenix.rails_commands
         WHERE attempts > 0 AND (leased_until IS NULL OR leased_until < now()))::integer AS retrying,
      (SELECT count(*) FROM phoenix.rails_commands_dead)::integer AS dead,
      (SELECT EXTRACT(EPOCH FROM now() - min(available_at))::integer FROM phoenix.rails_commands
         WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now())) AS oldest_due_seconds
  SQL

  OUTBOX_SQL = <<~SQL.squish
    SELECT
      count(*) FILTER (WHERE state = 'pending' AND scheduled_at <= now())::integer AS due,
      count(*) FILTER (WHERE state = 'pending' AND scheduled_at > now())::integer AS scheduled,
      count(*) FILTER (WHERE state = 'quarantined')::integer AS quarantined,
      EXTRACT(EPOCH FROM now() - min(scheduled_at) FILTER (WHERE state = 'pending' AND scheduled_at <= now()))::integer AS oldest_due_seconds
    FROM job_outbox
  SQL

  LEGACY_SCHEDULERS = {
    'cron:trek_sync_job' => 'Dawarich.Imports.Trek.ScheduleWorker',
    'cron:teslamate_sync_job' => 'Dawarich.Imports.Teslamate.ScheduleWorker'
  }.freeze

  DRAIN_SQL = <<~SQL.squish
    SELECT
      (SELECT count(*) FROM job_outbox WHERE state = 'pending')::integer AS pending_outbox,
      (SELECT count(*) FROM job_outbox WHERE state = 'pending' AND scheduled_at > now())::integer AS future_outbox,
      (SELECT count(*) FROM job_outbox WHERE state = 'quarantined')::integer AS quarantined,
      (SELECT count(*) FROM phoenix.rails_commands)::integer AS reverse_pending,
      (SELECT count(*) FROM phoenix.rails_commands WHERE available_at > now())::integer AS reverse_future,
      (SELECT count(*) FROM phoenix.rails_commands WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now()))::integer AS reverse_due,
      (SELECT count(*) FROM phoenix.rails_commands WHERE leased_until >= now())::integer AS reverse_leased,
      (SELECT count(*) FROM phoenix.rails_commands WHERE attempts > 0 AND (leased_until IS NULL OR leased_until < now()))::integer AS reverse_retrying,
      (SELECT count(*) FROM phoenix.rails_commands_dead)::integer AS reverse_dead,
      (SELECT count(*) FROM phoenix.release_operations WHERE status <> 'completed')::integer AS release_pending,
      (SELECT count(*) FROM oban.oban_jobs WHERE state NOT IN ('completed', 'cancelled'))::integer AS incomplete_oban,
      (SELECT count(*) FROM phoenix.track_generations g WHERE status <> 'completed' OR completed_chunks < total_chunks OR EXISTS (SELECT 1 FROM phoenix.track_generation_chunks c WHERE c.generation_id = g.id AND c.status <> 'completed'))::integer AS unfinished_generations,
      (SELECT count(*) FROM unnest(ARRAY[:keys]::text[]) AS expected(key) LEFT JOIN phoenix.job_owners o USING (key) WHERE o.key IS NULL)::integer AS missing_owners,
      (SELECT count(*) FROM phoenix.job_owners WHERE key = ANY(ARRAY[:keys]) AND owner <> 'oban')::integer AS mixed_owners,
      (SELECT count(*) FROM phoenix.job_owners WHERE NOT (key = ANY(ARRAY[:keys])))::integer AS unknown_owners,
      (SELECT count(*) FROM phoenix.job_owners WHERE key = ANY(ARRAY[:keys]) AND (owner <> 'sidekiq' OR NOT pinned))::integer AS unpinned_rollback_owners,
      (SELECT count(*) FROM phoenix.job_owners WHERE owner = 'oban')::integer AS oban_owners,
      (SELECT count(*) FROM phoenix.runtime_nodes WHERE beat_at > now() - interval '60 seconds')::integer AS fresh_nodes
  SQL
end
