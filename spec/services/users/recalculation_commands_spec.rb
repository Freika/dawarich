# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'timeout'

RSpec.describe 'Users::RecalculationCommands' do
  self.use_transactional_tests = false

  around do |example|
    connection = ActiveRecord::Base.connection
    sequence = connection.select_one('SELECT last_value, is_called FROM users_id_seq')
    example.run
  ensure
    connection.execute("SELECT setval('users_id_seq', #{sequence.fetch('last_value')}, " \
                       "#{connection.quote(sequence.fetch('is_called'))})")
  end

  before do
    phoenix_tables!
    @user = create(:user)
    @key = 'command:users.recalculate_data'
    job_owner!(@key, :sidekiq)
    job_owner!('command:achievements.check', :sidekiq)
    clear_enqueued_jobs
  end

  after do
    JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id).delete_all
    connection = ActiveRecord::Base.connection
    connection.execute('DELETE FROM phoenix.rails_commands ' \
                       "WHERE kind IN ('users.recalculate_data','achievements.check') " \
                       "AND payload->>'user_id'=#{connection.quote(@user.id.to_s)}")
    connection.execute("DELETE FROM phoenix.job_owners WHERE key=#{connection.quote(@key)}")
    connection.execute("DELETE FROM phoenix.job_owners WHERE key='command:achievements.check'")
    User.unscoped.where(id: @user.id).delete_all
    clear_enqueued_jobs
  end

  it 'user rebuild producer and reverse handler enqueue complete source jobs by current owner' do
    payload = {
      'user_id' => @user.id, 'year' => 2025, 'notify' => false, 'job_queue' => 'low_priority',
      'source_job_id' => SecureRandom.uuid, 'ambient_zone' => 'Asia/Tokyo'
    }
    due = Time.current.change(usec: 0) + 60
    expect(Users::RecalculationCommands.normalize(payload.merge('year' => '2025tail', 'notify' => '')))
      .to eq(payload.merge('notify' => true))
    expect(Users::RecalculationCommands.normalize(payload.merge('year' => 2025.9, 'notify' => nil)))
      .to eq(payload)
    JobCommands.produce('users.recalculate_data', payload, aggregate_id: @user.id,
                        producer: 'spec', scheduled_at: due)
    queued = enqueued_jobs.sole.deep_dup
    expect(queued.fetch('job_id')).to eq(payload['source_job_id'])
    expect(queued.fetch('timezone')).to eq('Asia/Tokyo')
    expect(queued.fetch('arguments')).to eq(
      [@user.id, { 'year' => 2025, 'notify' => false, 'job_queue' => 'low_priority',
                  '_aj_ruby2_keywords' => %w[year notify job_queue] }]
    )
    expect(Time.iso8601(queued.fetch('scheduled_at'))).to eq(due)
    clear_enqueued_jobs
    job_owner!(@key, :oban)
    ActiveJob::Base.deserialize(queued).perform_now
    row = JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id).sole
    expect(row).to have_attributes(event_id: payload['source_job_id'], payload:, scheduled_at: due)
    expect(enqueued_jobs).to be_empty
    JobOutbox.where(event_id: row.event_id).delete_all

    reverse = payload.merge('run_at' => due.to_i)
    connection = ActiveRecord::Base.connection
    statement = 'INSERT INTO phoenix.rails_commands (kind,payload) VALUES (?,?::jsonb)'
    connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, 'users.recalculate_data', reverse.to_json]))
    expect(RailsCommands::Poller.drain_once).to be >= 1
    expect(JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id).sole.payload).to eq(payload)
    expect(enqueued_jobs).to be_empty
    expect(JobCommands.rehome!('users.recalculate_data', by: 'spec')).to eq(moved: 1, left: 0)
    expect(enqueued_jobs.sole.fetch('job_id')).to eq(payload['source_job_id'])
    clear_enqueued_jobs
    connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, 'users.recalculate_data', reverse.to_json]))
    RailsCommands::Poller.drain_once
    expect(enqueued_jobs.sole.fetch('job_id')).to eq(payload['source_job_id'])
    expect(enqueued_jobs.sole.fetch('arguments')).to eq(queued.fetch('arguments'))
    expect(enqueued_jobs.sole.fetch('timezone')).to eq('Asia/Tokyo')
    expect(JobOutbox.where(command_type: 'users.recalculate_data', aggregate_id: @user.id)).to be_empty

    clear_enqueued_jobs
    corpus = JSON.parse(File.read(Rails.root.join('app-phoenix/test/fixtures/a12d1b3/recalculations.json')))
                 .fetch('cases').find { _1.fetch('id') == 'backfill_async' }
    rebuild_id = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE,
                                      "anomaly_backfill.rebuild:#{corpus.fetch('job').fetch('job_id')}")
    reset_payload = {
      'user_id' => @user.id, 'year' => nil, 'notify' => true, 'job_queue' => nil,
      'source_job_id' => rebuild_id,
      'ambient_zone' => corpus.fetch('job').fetch('timezone'), 'run_at' => due.to_i
    }
    achievement = { 'user_id' => @user.id, 'notify' => true, 'oldest_timestamp' => 1_735_687_800,
                    'run_at' => due.to_i }
    connection.execute(ActiveRecord::Base.sanitize_sql_array(
                         [statement, 'users.recalculate_data', reset_payload.to_json]
                       ))
    connection.execute(ActiveRecord::Base.sanitize_sql_array(
                         [statement, 'achievements.check', achievement.to_json]
                       ))
    RailsCommands::Poller.drain_once
    rebuilt = enqueued_jobs.find { _1.fetch('job_class') == 'Users::RecalculateDataJob' }
    checked = enqueued_jobs.find { _1.fetch('job_class') == 'Achievements::CheckJob' }
    expect(rebuilt.fetch('job_id')).to eq(reset_payload.fetch('source_job_id'))
    expect(rebuilt.fetch('timezone')).to eq(reset_payload.fetch('ambient_zone'))
    expect(rebuilt.fetch('arguments')).to eq(
      [@user.id, { 'year' => nil, 'notify' => true, 'job_queue' => nil,
                  '_aj_ruby2_keywords' => %w[year notify job_queue] }]
    )
    expect(checked).not_to be_nil
    expect(checked.fetch('arguments')).to eq(
      [@user.id, { 'notify' => true, 'oldest_timestamp' => 1_735_687_800,
                  '_aj_ruby2_keywords' => %w[notify oldest_timestamp] }]
    )
  end

  it 'recalculation database guard refuses non-test Rails and Phoenix database names' do
    expect { recalculation_database!('dawarich_production', 'dawarich_test_example') }
      .to raise_error(ArgumentError, 'recalculation peers require test databases')
    expect { recalculation_database!('dawarich_phoenix_test_example', 'dawarich_production') }
      .to raise_error(ArgumentError, 'recalculation peers require test databases')
  end

  def recalculation_database!(phoenix_database = ENV.fetch('PHOENIX_TEST_DATABASE'),
                              rails_database = ENV.fetch('DATABASE_NAME'))
    unless phoenix_database.start_with?('dawarich_phoenix_test') && rails_database.start_with?('dawarich_test')
      raise ArgumentError, 'recalculation peers require test databases'
    end

    "#{phoenix_database}_scratch"
  end

  it 'actual Rails and native peers share K5 and anomaly lease exclusion' do
    original_config = ActiveRecord::Base.connection_db_config.configuration_hash
    fixture_mode = self.class.use_transactional_tests
    shared_database = recalculation_database!
    command = %w[mix test test/dawarich/jobs/recalculation_lifecycle_test.exs
                 --include rails_parity --only rails_parity --seed 101]
    messages = Queue.new
    output = +''
    errors = +''
    stdin, stdout, stderr, peer = Open3.popen3(
      { 'PHOENIX_TEST_DATABASE' => ENV.fetch('PHOENIX_TEST_DATABASE'), 'SELF_HOSTED' => 'false' }, *command,
      chdir: Rails.root.join('app-phoenix').to_s
    )
    reader = Thread.new do
      stdout.each_line do |line|
        output << line
        messages << JSON.parse(line.delete_prefix('A12D1B3:')) if line.start_with?('A12D1B3:')
      end
      messages << { 'op' => 'eof' }
    end
    error_reader = Thread.new { errors << stderr.read }
    expect(recalculation_message(messages)).to eq('op' => 'ready', 'database' => shared_database)
    ActiveRecord::Base.establish_connection(original_config.merge(database: shared_database))
    connected = true
    source = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12d1b3/recalculations.json').read)
                 .fetch('cases').find { _1.fetch('id') == 'full' }
    connection = ActiveRecord::Base.connection
    source.fetch('input').each do |table, rows|
      rows.each do |row|
        columns = row.keys.sort.map { connection.quote_column_name(_1) }.join(', ')
        connection.execute("INSERT INTO public.#{table} (#{columns}) SELECT #{columns} " \
                           "FROM json_populate_record(NULL::public.#{table}, #{connection.quote(row.to_json)}::json)")
      end
    end
    connection.execute('UPDATE points SET anomaly=true WHERE id=170201')
    job_owner!('command:stats.full_recalculation', :oban)
    job_owner!('command:stats.calculate_month', :sidekiq)
    clear_enqueued_jobs
    debouncer = Stats::RecalculationDebouncer.new(170_101)
    debouncer.trigger
    initial = enqueued_jobs.sole.deep_dup
    clear_enqueued_jobs
    ActiveJob::Base.deserialize(initial).perform_now
    connection.execute("UPDATE job_outbox SET scheduled_at=NOW() WHERE event_id=#{connection.quote(initial['job_id'])}")
    recalculation_send(stdin, op: 'full')
    held = recalculation_message(messages)
    expect(held.fetch('op')).to eq('full_held')
    ready = Queue.new
    trigger = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |db|
        ready << db.select_value('SELECT pg_backend_pid()')
        Stats::RecalculationDebouncer.new(170_101).trigger
      end
    end
    waiting = Timeout.timeout(5) { ready.pop }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC)).to be < deadline
      break if connection.select_value("SELECT #{held.fetch('pid').to_i}=ANY(pg_blocking_pids(#{waiting.to_i}))")
    end
    recalculation_send(stdin, op: 'finish')
    expect(recalculation_message(messages)).to eq('op' => 'full_done')
    expect(trigger.join(5)).to eq(trigger)
    trigger.value
    expect(enqueued_jobs.size).to eq(1)
    k5_query = "SELECT expires_at>NOW() FROM phoenix.once_claims WHERE key='stats_full_recalculation:user:170101'"
    expect(connection.select_value(k5_query))
      .to be(true)
    recalculation_send(stdin, op: 'replay')
    expect(recalculation_message(messages)).to eq('op' => 'replayed')
    expect(connection.select_value(k5_query))
      .to be(true)
    expect(connection.select_value("SELECT count(*) FROM phoenix.rails_commands WHERE kind='stats.calculate_month'"))
      .to eq(4)
    later = enqueued_jobs.sole.deep_dup
    clear_enqueued_jobs
    ActiveJob::Base.deserialize(later).perform_now
    expect(JobCommands.rehome!('stats.full_recalculation', by: 'shared-peer')).to eq(moved: 1, left: 0)
    expect(JobCommands.rehome!('stats.full_recalculation', by: 'shared-peer')).to eq(moved: 0, left: 0)
    expect(enqueued_jobs.sole.fetch('job_id')).to eq(later.fetch('job_id'))
    expect(JobOutbox.find(initial.fetch('job_id')).state).to eq('dispatched')
    clear_enqueued_jobs

    expect(PhoenixLease.try_hold('anomaly_backfill:170101') do
      recalculation_send(stdin, op: 'rails_lease')
      expect(recalculation_message(messages)).to eq('op' => 'native_busy')
      expect(Point.find(170_201).anomaly).to be(true)
      true
    end).to be(true)
    recalculation_send(stdin, op: 'native_lease')
    expect(recalculation_message(messages)).to eq('op' => 'native_held')
    expect(Points::AnomalyBackfillUserJob.new.perform(170_101, reset: true, notify: false)).to be(false)
    expect(Point.find(170_201).anomaly).to be(true)
    expect(enqueued_jobs).to be_empty
    expect(connection.select_value("SELECT count(*) FROM phoenix.leases WHERE name='anomaly_backfill:170101'"))
      .to eq(1)
    recalculation_send(stdin, op: 'finish')
    expect(recalculation_message(messages)).to eq('op' => 'native_done')
    recalculation_send(stdin, op: 'stop')
    expect(recalculation_message(messages)).to eq('op' => 'done')
    stdin.close
    expect(peer.join(5)).to eq(peer)
    reader.join
    error_reader.join
    puts output
    expect(peer.value.success?).to be(true), output + errors
    expect(output).to match(/4 tests, 0 failures, 3 excluded/)
  ensure
    trigger&.kill if trigger&.alive?
    trigger&.join
    stdin&.close unless stdin&.closed?
    if peer && !peer.join(5)
      Process.kill('TERM', peer.pid)
      peer.join
    end
    reader&.join
    error_reader&.join
    puts output if output && $ERROR_INFO
    warn errors if errors.present? && $ERROR_INFO
    clean_recalculation_peer(initial&.fetch('job_id')) if connected
    ActiveRecord::Base.establish_connection(original_config) if original_config
    self.class.use_transactional_tests = fixture_mode unless fixture_mode.nil?
  end

  def recalculation_message(queue) = Timeout.timeout(5) { queue.pop }

  def recalculation_send(input, message)
    input.puts(JSON.generate(message))
    input.flush
  end

  def clean_recalculation_peer(event_id)
    connection = ActiveRecord::Base.connection
    [Notification, Stat, Users::Digest, Point, Track].each { _1.where(user_id: 170_101).delete_all }
    JobOutbox.where(aggregate_id: 170_101).delete_all
    connection.execute("DELETE FROM phoenix.rails_commands WHERE payload->>'user_id'='170101'")
    connection.execute("DELETE FROM phoenix.once_claims WHERE key='stats_full_recalculation:user:170101'")
    connection.execute("DELETE FROM phoenix.leases WHERE name='anomaly_backfill:170101'")
    backfill_event = '00000000-0000-4000-8000-000000170998'
    progress_key = connection.quote("anomaly_backfill:progress:#{backfill_event}")
    connection.execute("DELETE FROM phoenix.cursors WHERE key=#{progress_key}")
    connection.execute("DELETE FROM phoenix.processed_commands WHERE event_id=#{connection.quote(backfill_event)}")
    if event_id
      connection.execute("DELETE FROM phoenix.processed_commands WHERE event_id=#{connection.quote(event_id)}")
    end
    connection.execute('DELETE FROM phoenix.job_owners WHERE key IN ' \
                       "('command:stats.full_recalculation','command:stats.calculate_month')")
    connection.execute("DELETE FROM oban.oban_jobs WHERE args->>'user_id'='170101'")
    User.unscoped.where(id: 170_101).delete_all
  end
end
