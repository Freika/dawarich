# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobHealth do
  before { described_class.reset! }

  def beat!(node, seconds_ago)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, node, seconds_ago]))
      INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at)
      VALUES (?, now() - interval '1 hour', now() - make_interval(secs => ?))
    SQL
  end

  def sql_during(&)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    statements
  end

  it 'reports a container without a BEAM as absent, and no alarm before Phoenix ever migrated' do
    expect(described_class.compute(nil)).to eq(status: 'absent', alarm: false)
    expect(described_class.compute('web-1')).to eq(status: 'stale', alarm: false)
  end

  it 'reports ok while this node beats' do
    phoenix_tables!
    beat!('web-1', 5)

    expect(described_class.compute('web-1')).to eq(status: 'ok', alarm: false)
  end

  it 'raises the alarm when Oban owns a key and no node has beaten for a minute, cron keys included' do
    job_owner!('cron:app_version_checking_job', :oban)
    beat!('web-1', 120)

    expect(described_class.compute('web-1')).to eq(status: 'stale', alarm: true)
    expect(described_class.compute(nil)).to eq(status: 'absent', alarm: true)
  end

  it 'raises the alarm when a due command waits longer than five minutes, even with a live node' do
    phoenix_tables!
    beat!('web-1', 5)
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'trips.calculate', command_version: 1,
                      payload: { 'trip_id' => 1, 'distance_unit' => 'km' }, scheduled_at: 10.minutes.ago)

    expect(described_class.compute('web-1')).to eq(status: 'ok', alarm: true)
  end

  it 'counts the outbox, owners, nodes and Oban jobs per worker and state, cancelled included' do
    job_owner!('command:trips.calculate', :oban)
    beat!('web-1', 5)
    JobOutbox.create!(event_id: SecureRandom.uuid, command_type: 'trips.calculate', command_version: 1,
                      payload: { 'trip_id' => 1, 'distance_unit' => 'km' }, scheduled_at: 2.minutes.ago)
    connection = ActiveRecord::Base.connection
    connection.execute('CREATE SCHEMA oban')
    connection.execute('CREATE TABLE oban.oban_jobs (worker text, state text)')
    connection.execute("INSERT INTO oban.oban_jobs VALUES ('Dawarich.Trips.CalculateWorker', 'cancelled')")

    gauges = described_class.gauges

    expect(gauges[:outbox]).to include('due' => 1, 'scheduled' => 0, 'quarantined' => 0)
    expect(gauges[:outbox]['oldest_due_seconds']).to be >= 119
    expect(gauges[:owners].map { _1.slice('key', 'owner') })
      .to eq([{ 'key' => 'command:trips.calculate', 'owner' => 'oban' }])
    expect(gauges[:nodes].map { _1['node'] }).to eq(['web-1'])
    expect(gauges[:oban])
      .to eq([{ 'worker' => 'Dawarich.Trips.CalculateWorker', 'state' => 'cancelled', 'count' => 1 }])
  end

  it 'counts due, leased, retrying and dead reverse-outbox rows' do
    phoenix_tables!
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.rails_commands (kind, payload, attempts, available_at)
      VALUES ('visit_months_changed', '{}', 0, now()), ('visit_months_changed', '{}', 3, now()),
             ('visit_months_changed', '{}', 1, now()),
             ('visit_months_changed', '{}', 0, now() + interval '1 hour')
    SQL
    connection.execute(<<~SQL.squish)
      UPDATE phoenix.rails_commands SET leased_until = now() + interval '1 minute'
      WHERE attempts = 1 AND available_at <= now()
    SQL
    connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.rails_commands_dead (id, kind, payload, attempts, last_error, created_at)
      VALUES (999_999, 'visit_months_changed', '{}', 25, 'RuntimeError: cache down', now())
    SQL

    gauges = described_class.gauges

    expect(gauges[:rails_commands]).to include('due' => 2, 'leased' => 1, 'retrying' => 1, 'dead' => 1)
    expect(gauges[:rails_commands]['oldest_due_seconds']).to be >= 0
  end

  it 'reports no reverse-outbox gauge before Phoenix migrated its tables' do
    connection = ActiveRecord::Base.connection
    connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    job_control = Rails.root.join('app-phoenix/priv/repo/sql/20260927120100_job_control.sql')
    File.read(job_control).split(";\n").map(&:strip).reject(&:empty?).each { connection.execute(_1) }

    gauges = described_class.gauges

    expect(gauges[:tables]).to be(true)
    expect(gauges[:rails_commands]).to be_nil
  end

  it 'warns once at boot when this container runs Puma without Phoenix' do
    allow(Rails.logger).to receive(:warn)

    described_class.warn_if_absent({})
    described_class.warn_if_absent({ 'DAWARICH_PHOENIX_NODE' => 'web-1' })

    expect(Rails.logger).to have_received(:warn).once.with(/not running in this container/)
  end

  it 'sets the statement timeout before its first query, the table check included' do
    job_owner!('cron:app_version_checking_job', :oban)

    statements = sql_during { described_class.compute('web-1') }.grep_v(/\A(SAVEPOINT|RELEASE SAVEPOINT|BEGIN|COMMIT)/)

    expect(statements.first).to eq("SET LOCAL statement_timeout = '500ms'")
    expect(statements.second).to include("to_regclass('phoenix.job_owners')")
  end

  it 'hands the connection back to the pool after a refresh on the refresher thread' do
    job_owner!('cron:app_version_checking_job', :oban)
    refreshing = Thread.new do
      described_class.refresh!('web-1')
      ActiveRecord::Base.connection_pool.active_connection?
    end

    expect(refreshing.join(5)).to be(refreshing)
    expect(refreshing.value).to be_nil
  ensure
    refreshing&.kill&.join(5)
  end

  describe 'the cached summary the health endpoint reads' do
    it 'reads unknown before the first refresh' do
      expect(described_class.summary).to eq(status: 'unknown', alarm: false)
    end

    it 'answers from the refreshed value without touching the database' do
      job_owner!('cron:app_version_checking_job', :oban)
      described_class.refresh!(nil)

      statements = sql_during { expect(described_class.summary).to eq(status: 'absent', alarm: true) }

      expect(statements).to eq([])
    end

    it 'reads unknown when the last refresh is older than a minute' do
      before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.refresh!(nil)
      after = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect(described_class.summary(before + 60)).to eq(status: 'absent', alarm: false)
      expect(described_class.summary(after + 61)).to eq(status: 'unknown', alarm: false)
    end
  end

  describe 'the refresher' do
    def refreshers = Thread.list.select { _1.name == 'job-health-refresher' }

    after { refreshers.each { _1.kill.join(5) } }

    it 'starts once per process on the first summary, and again once its thread is gone, as in a forked worker' do
      ticks = Queue.new
      allow(described_class).to receive(:refresh!) { ticks << Thread.current }
      allow(Rails.env).to receive(:test?).and_return(false)

      described_class.summary
      first = ticks.pop(timeout: 5)
      described_class.summary

      expect(refreshers).to eq([first])

      first.kill.join(5)
      described_class.summary
      second = ticks.pop(timeout: 5)

      expect(second).to be_a(Thread)
      expect(refreshers).to eq([second])
      expect(second).not_to be(first)
    end

    it 'keeps refreshing after a refresh fails' do
      ticks = Queue.new
      calls = 0
      allow(described_class).to receive(:refresh!) do
        calls += 1
        ticks << calls
        raise PG::ConnectionBad, 'gone' if calls == 1
      end
      allow(Rails.logger).to receive(:warn)

      described_class.start_refresher(interval: 0)

      expect([ticks.pop(timeout: 5), ticks.pop(timeout: 5)]).to eq([1, 2])
      expect(Rails.logger).to have_received(:warn).with('[JobHealth] refresh failed: PG::ConnectionBad')
    end

    it 'refreshes whichever JobHealth is loaded at each tick, so a code reload does not strand the cache' do
      allow(described_class).to receive(:refresh!)
      described_class.start_refresher(interval: 0)
      ticks = Queue.new
      reloaded = Module.new
      reloaded.define_singleton_method(:refresh!) { ticks << :reloaded }

      stub_const('JobHealth', reloaded)

      expect(ticks.pop(timeout: 5)).to eq(:reloaded)
    end

    it 'answers the health endpoint from the cache when the refresher cannot start' do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(Thread).to receive(:new).and_raise(ThreadError, "can't create Thread")
      allow(Rails.logger).to receive(:warn)

      expect(described_class.summary).to eq(status: 'unknown', alarm: false)
      expect(Rails.logger).to have_received(:warn).with('[JobHealth] refresher failed to start: ThreadError')
    end
  end

  it 'reports unknown gauges instead of failing the admin page when the database errors' do
    phoenix_tables!
    ActiveRecord::Base.connection.execute('DROP TABLE job_outbox')
    allow(Rails.logger).to receive(:warn)

    expect(described_class.gauges).to eq(tables: :unknown)
    expect(Rails.logger).to have_received(:warn).with(/\A\[JobHealth\] gauges failed: /)
  end
end
