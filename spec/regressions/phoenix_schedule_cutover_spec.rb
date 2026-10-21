# frozen_string_literal: true

require 'rails_helper'
require 'open3'
require 'timeout'

RSpec.describe 'Phoenix schedule cutover' do
  self.use_transactional_tests = false

  it 'concurrent Rails cron native slot and owner flip yield one committed fanout and recover from publish failure' do
    original = ActiveRecord::Base.connection_db_config.configuration_hash
    phoenix = ENV.fetch('PHOENIX_TEST_DATABASE')
    unless phoenix.start_with?('dawarich_phoenix_test') && ENV.fetch('DATABASE_NAME').start_with?('dawarich_test')
      raise ArgumentError, 'schedule peers require test databases'
    end

    messages = Queue.new
    output = +''
    errors = +''
    peer_env = {
      'PATH' => "#{ENV.fetch('HOME')}/.asdf/shims:#{ENV.fetch('PATH')}",
      'ASDF_ERLANG_VERSION' => '27.3.4.1', 'ASDF_ELIXIR_VERSION' => '1.18.3-otp-27',
      'DATABASE_HOST' => '127.0.0.1', 'PHOENIX_TEST_DATABASE' => phoenix,
      'PHOENIX_TEST_REDIS_URL' => ENV.fetch('PHOENIX_TEST_REDIS_URL'), 'MIX_ENV' => 'test'
    }
    compile_output, compile_errors, compile_status = Open3.capture3(
      peer_env, 'mix', 'compile', chdir: Rails.root.join('app-phoenix').to_s
    )
    expect(compile_status.success?).to be(true), compile_output + compile_errors
    command = %w[mix test --no-compile test/dawarich/jobs/schedule_cutover_test.exs
                 --include rails_parity --only rails_parity --seed 202]
    stdin, stdout, stderr, peer = Open3.popen3(peer_env, *command, chdir: Rails.root.join('app-phoenix').to_s)
    reader = Thread.new do
      stdout.each_line do |line|
        output << line
        messages << JSON.parse(line.delete_prefix('A12D3:')) if line.start_with?('A12D3:')
      end
      messages << { 'op' => 'eof' }
    end
    error_reader = Thread.new { errors << stderr.read }
    ready = receive_peer(messages, timeout: 120)
    expect(ready.fetch('op')).to eq('ready'), output + errors
    expect(ready.fetch('database')).to eq("#{phoenix}_scratch")
    ActiveRecord::Base.establish_connection(original.merge(database: ready.fetch('database')))
    connected = true
    PhoenixSchema.reset!
    key = 'cron:teslamate_sync_job'
    db = ActiveRecord::Base.connection
    clear_enqueued_jobs
    due = Time.iso8601('2025-10-26T02:30:00+01:00')
    slot = due.to_i / 60 * 60

    JobOwnership.with_owner(key) do
      send_peer(stdin, op: 'claim', expected: '{:error, :lock_not_available}')
      expect(receive_peer(messages)).to eq('op' => 'claimed')
      source_schedule(due)
    end
    expect(enqueued_jobs.count { _1.fetch('job_class') == 'TeslaMate::SyncJob' }).to eq(1)
    send_peer(stdin, op: 'claim', expected: ':claimed')
    expect(receive_peer(messages)).to eq('op' => 'claimed')
    send_peer(stdin, op: 'run', slot: slot)
    expect(receive_peer(messages)).to eq('op' => 'ran')
    expect(db.select_value('SELECT count(*) FROM phoenix.rails_commands')).to eq(0)
    JobOwnership.release!(key, by: 'schedule-peer')
    source_schedule(due)
    expect(enqueued_jobs.count { _1.fetch('job_class') == 'TeslaMate::SyncJob' }).to eq(1)
    send_peer(stdin, op: 'claim', expected: ':pinned')
    expect(receive_peer(messages)).to eq('op' => 'claimed')

    db.execute('ALTER TABLE phoenix.rails_commands ADD CONSTRAINT a12d3_publish_failure ' \
               "CHECK (kind <> 'integrations.teslamate_sync')")
    expect { source_schedule(due + 60) }.to raise_error(ActiveRecord::StatementInvalid, /a12d3_publish_failure/)
    expect(db.select_value('SELECT count(*) FROM phoenix.processed_commands')).to eq(1)
    db.execute('ALTER TABLE phoenix.rails_commands DROP CONSTRAINT a12d3_publish_failure')
    JobOwnership.unpin!(key, by: 'schedule-peer')
    send_peer(stdin, op: 'claim', expected: ':claimed')
    expect(receive_peer(messages)).to eq('op' => 'claimed')
    send_peer(stdin, op: 'hold', slot: slot + 60)
    held = receive_peer(messages)
    expect(held.fetch('op')).to eq('held')
    started = Queue.new
    release = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        started << connection.select_value('SELECT pg_backend_pid()')
        JobOwnership.release!(key, by: 'schedule-peer')
      end
    end
    waiting = Timeout.timeout(5) { started.pop }
    Timeout.timeout(5) do
      loop do
        break if db.select_value("SELECT #{held.fetch('pid').to_i}=ANY(pg_blocking_pids(#{waiting.to_i}))")
      end
    end
    send_peer(stdin, op: 'finish')
    expect(receive_peer(messages)).to eq('op' => 'ran')
    expect(release.join(5)).to eq(release)
    release.value
    expect(RailsCommands::Poller.drain_once).to eq(1)
    source_schedule(due + 60)
    expect(enqueued_jobs.count { _1.fetch('job_class') == 'TeslaMate::SyncJob' }).to eq(2)
    expect(db.select_rows("SELECT owner,pinned FROM phoenix.job_owners WHERE key='#{key}'"))
      .to eq([['sidekiq', true]])
    expect(db.select_value('SELECT count(*) FROM phoenix.processed_commands')).to eq(2)
    send_peer(stdin, op: 'stop')
    expect(receive_peer(messages)).to eq('op' => 'done')
    stdin.close
    expect(peer.join(5)).to eq(peer)
    reader.join
    error_reader.join
    expect(peer.value.success?).to be(true), output + errors
    puts output
  ensure
    release&.kill if release&.alive?
    release&.join
    stdin&.close unless stdin&.closed?
    if peer && !peer.join(5)
      Process.kill('TERM', peer.pid)
      peer.join
    end
    reader&.join
    error_reader&.join
    puts output if output && $ERROR_INFO
    warn errors if errors.present? && $ERROR_INFO
    if connected
      db.execute('ALTER TABLE phoenix.rails_commands DROP CONSTRAINT IF EXISTS a12d3_publish_failure')
      %w[phoenix.rails_commands phoenix.processed_commands phoenix.job_owners].each do |table|
        db.execute("DELETE FROM #{table}")
      end
      db.execute('DELETE FROM trip_sources')
      User.unscoped.where(id: ready.fetch('user')).delete_all
    end
    ActiveRecord::Base.establish_connection(original) if original
    PhoenixSchema.reset!
    clear_enqueued_jobs
  end

  def source_schedule(due)
    job = TeslaMate::SyncSchedulingJob.new('a12d2_cron')
    job.enqueued_at = due
    job.perform_now
  end

  def receive_peer(messages, timeout: 5) = Timeout.timeout(timeout) { messages.pop }

  def send_peer(input, message)
    input.puts(JSON.generate(message))
    input.flush
  end
end
