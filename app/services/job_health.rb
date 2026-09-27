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

  def gauges
    read do
      next { tables: false } unless JobOwnership.table?

      {
        tables: true,
        outbox: connection.select_one(OUTBOX_SQL),
        owners: connection.select_all(OWNERS_SQL).to_a,
        nodes: connection.select_all(NODES_SQL).to_a,
        oban: oban_counts
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[JobHealth] gauges failed: #{e.class}")
    { tables: :unknown }
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

  OUTBOX_SQL = <<~SQL.squish
    SELECT
      count(*) FILTER (WHERE state = 'pending' AND scheduled_at <= now())::integer AS due,
      count(*) FILTER (WHERE state = 'pending' AND scheduled_at > now())::integer AS scheduled,
      count(*) FILTER (WHERE state = 'quarantined')::integer AS quarantined,
      EXTRACT(EPOCH FROM now() - min(scheduled_at) FILTER (WHERE state = 'pending' AND scheduled_at <= now()))::integer AS oldest_due_seconds
    FROM job_outbox
  SQL
end
