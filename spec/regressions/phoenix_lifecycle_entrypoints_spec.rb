# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'uri'

RSpec.describe 'Phoenix lifecycle entrypoints' do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:stubs) { Dir.mktmpdir('phoenix-lifecycle') }
  let(:calls_file) { File.join(stubs, 'calls.log') }
  let(:server) { ['puma', '-C', 'config/puma.rb', '-p', '5000', '--tag', 'two words'] }

  after { FileUtils.remove_entry(stubs) }

  before do
    %w[createdb psql].each { |name| stub_command(name, 'exit 0') }
    stub_command('id', 'echo 1000')
    stub_command('bundle', %(printf '%s\\n' "bundle $*" >> "#{calls_file}"))
    stub_command('dawarich', <<~SH)
      if [ "$1" = start ]; then
        printf '%s\\n' "dawarich start $(printf '%s' "$DAWARICH_RAILS_ARGS" | tr '\\037' '|')" >> "#{calls_file}"
        exit 0
      fi
      printf '%s\\n' "dawarich $*" >> "#{calls_file}"
      case "$1" in
        migrate) exit "${STUB_MIGRATE_STATUS:-0}" ;;
        seeds) exit "${STUB_SEEDS_STATUS:-0}" ;;
        eval) exit "${STUB_READY_STATUS:-0}" ;;
      esac
    SH
  end

  def stub_command(name, body)
    path = File.join(stubs, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def run_script(name, *args, **env)
    FileUtils.rm_f(calls_file)
    base = {
      'PATH' => "#{stubs}:#{ENV.fetch('PATH')}", 'APP_PATH' => stubs, 'RAILS_ENV' => 'test',
      'PUID' => nil, 'PGID' => nil, 'DATABASE_URL' => nil, 'DATABASE_HOST' => '127.0.0.1',
      'DATABASE_NAME' => 'dawarich_test_a12h', 'DATABASE_PASSWORD' => '',
      'DAWARICH_PHOENIX_LIFECYCLE' => 'true', 'SELF_HOSTED' => 'true'
    }
    _, stderr, status = Open3.capture3(base.merge(env.transform_keys(&:to_s)), 'sh',
                                       File.join(root, 'docker', name), *args)
    calls = File.exist?(calls_file) ? File.readlines(calls_file, chomp: true) : []
    { stderr:, status:, calls: }
  end

  def rails_probe(code)
    raise ArgumentError, 'Rails probes require RAILS_ENV=test' unless ENV.fetch('RAILS_ENV') == 'test'

    env = {
      'SELF_HOSTED' => 'false', 'DAWARICH_CLOUD_DRAIN_ONLY' => 'false',
      'DAWARICH_PHOENIX_LIFECYCLE' => 'false', 'DATABASE_URL' => nil,
      'REDIS_URL' => test_redis_url, 'RAILS_JOB_QUEUE_DB' => '1', 'RAILS_CACHE_DB' => '0'
    }
    stdout, stderr, status = Open3.capture3(env, 'asdf', 'exec', 'bundle', 'exec', 'ruby', '-e', code, chdir: root)
    expect(status).to be_success, "Rails probe failed: #{stderr.lines.last(8).join}"
    JSON.parse(stdout.lines.find { |line| line.start_with?('DRAIN_PROBE=') }.delete_prefix('DRAIN_PROBE='))
  end

  def test_redis_url
    url = URI.parse(ENV.fetch('REDIS_URL'))
    unless %w[redis rediss].include?(url.scheme) && %w[127.0.0.1 localhost [::1]].include?(url.host) &&
           url.port&.between?(1, 65_535) && ![6379, 7205].include?(url.port) &&
           url.path.match?(%r{\A(?:/\d*)?\z}) && url.query.nil? && url.fragment.nil?
      raise ArgumentError, 'Rails probes require a private test Redis URL'
    end

    url.path = ''
    url.to_s
  rescue URI::InvalidURIError, KeyError, TypeError
    raise ArgumentError, 'Rails probes require a private test Redis URL'
  end

  it 'Rails probes preserve the caller Redis target with separate queue and cache databases' do
    url = URI.parse(ENV.fetch('REDIS_URL'))
    url.port = url.port == 65_535 ? url.port - 1 : url.port + 1
    url.path = '/7'
    stub_const('ENV', { 'RAILS_ENV' => 'test', 'REDIS_URL' => url.to_s })
    url.path = ''
    expect(Open3).to receive(:capture3).with(
      hash_including('REDIS_URL' => url.to_s, 'RAILS_JOB_QUEUE_DB' => '1', 'RAILS_CACHE_DB' => '0'),
      'asdf', 'exec', 'bundle', 'exec', 'ruby', '-e', 'probe', chdir: root
    ).and_return(["DRAIN_PROBE={}\n", '', instance_double(Process::Status, success?: true)])

    expect(rails_probe('probe')).to eq({})
  end

  it 'Rails probes reject unsafe Redis targets before launching destructive cleanup' do
    expect(Open3).not_to receive(:capture3)
    env = { 'RAILS_ENV' => 'test' }
    stub_const('ENV', env)
    [nil, '', 'not a URL', 'http://127.0.0.1:12345', 'redis://example.com:12345',
     'redis://127.0.0.1', 'redis://127.0.0.1:6379', 'redis://127.0.0.1:7205'].each do |url|
      env['REDIS_URL'] = url
      expect { rails_probe('probe') }.to raise_error(ArgumentError, 'Rails probes require a private test Redis URL')
    end
    env['RAILS_ENV'] = 'production'
    expect { rails_probe('probe') }.to raise_error(ArgumentError, 'Rails probes require RAILS_ENV=test')
  end

  it 'drain only Rails boot disables cache cron loading cron polling and reverse poller' do
    result = rails_probe(<<~RUBY)
      require 'sidekiq/cli'
      require 'sidekiq-cron'
      require 'json'
      Sidekiq.configure_server { |c| c.redis = { url: ENV.fetch('REDIS_URL'), db: 1 } }
      Sidekiq.redis { |r| r.call('FLUSHDB') }
      Sidekiq::Cron::Job.create(name: 'drain-stale', cron: '* * * * *', class: 'Cache::CleaningJob')
      require 'redis'
      Redis.new(url: ENV.fetch('REDIS_URL'), db: 0).flushdb
      ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'true'
      module Rails; class Server; end; end
      require './config/environment'
      calls = []
      observer = Module.new do
        define_method(:start) { calls << :reverse; super() }
      end
      RailsCommands::Poller.singleton_class.prepend(observer)
      Sidekiq.default_configuration[:lifecycle_events][:startup].each(&:call)
      launcher = Sidekiq::Launcher.new(Sidekiq.default_configuration, embedded: true)
      puts 'DRAIN_PROBE=' + JSON.generate(
        enabled: Sidekiq::Cron.configuration.enabled,
        interval: Sidekiq::Cron.configuration.cron_poll_interval,
        poller: !launcher.cron_poller.nil?,
        registrations: Sidekiq::Cron::Job.all.map(&:name), reverse_starts: calls.length,
        cache_jobs: Sidekiq::Queue.all.flat_map { |q| q.map { |j| j.item['wrapped'] } },
        queued: Sidekiq::Queue.all.sum(&:size)
      )
      RailsCommands::Poller.stop
      Sidekiq.redis { |r| r.call('FLUSHDB') }
    RUBY
    expect(result).to include('enabled' => false, 'interval' => 0, 'poller' => false,
                              'registrations' => ['drain-stale'], 'reverse_starts' => 0,
                              'cache_jobs' => [], 'queued' => 0)
  end

  it 'drain only rejects new callback manual and framework source enqueues without acknowledging them' do
    result = rails_probe(<<~RUBY)
      require './config/environment'
      require 'sidekiq/api'
      require 'json'
      ActiveJob::Base.queue_adapter = :sidekiq
      class DrainProbeJob < ApplicationJob; def perform; end; end
      Sidekiq.redis { |r| r.call('FLUSHDB') }
      original = DrainProbeJob.perform_later
      future = DrainProbeJob.set(wait: 60).perform_later
      snapshot = -> { Sidekiq.redis { |r| r.call('LRANGE', 'queue:default', 0, -1) } +
                      Sidekiq::ScheduledSet.new.map(&:jid) }
      before = snapshot.call
      ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'true'
      attempts = [
        -> { User.new(id: 991).send(:trigger_creation_webhook) },
        -> { DrainProbeJob.perform_later },
        -> { DrainProbeJob.set(wait: 10).perform_later },
        -> { ActiveJob.perform_all_later(DrainProbeJob.new) },
        -> { ActiveStorage::PurgeJob.perform_later(nil) },
        -> { Sidekiq::Client.push('class' => 'DrainProbe', 'args' => []) },
        -> { Sidekiq::Client.new.push_bulk('class' => 'DrainProbe', 'args' => [[], []]) }
      ]
      errors = attempts.map do |attempt|
        begin
          attempt.call
          'acknowledged'
        rescue StandardError => e
          e.class.name
        end
      end
      after = snapshot.call
      Sidekiq.redis { |r| r.call('ZADD', 'schedule', Time.now.to_f - 1,
        Sidekiq::ScheduledSet.new.first.value) }
      Sidekiq::Scheduled::Enq.new(Sidekiq.default_configuration).enqueue_jobs(['schedule'])
      transferred = Sidekiq::Queue.new('default').map(&:jid).include?(future.provider_job_id)
      ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'false'
      resumed = DrainProbeJob.perform_later
      puts 'DRAIN_PROBE=' + JSON.generate(errors: errors, unchanged: before == after,
        original: !original.provider_job_id.nil?, future: !future.provider_job_id.nil?,
        resumed: !resumed.provider_job_id.nil?, transferred: transferred)
      Sidekiq.redis { |r| r.call('FLUSHDB') }
    RUBY
    expect(result).to include('errors' => Array.new(7, 'CloudDrain::EnqueueRefused'), 'unchanged' => true,
                              'original' => true, 'future' => true, 'resumed' => true, 'transferred' => true)
  end

  it 'drain only prevents fresh source job commands but retains accepted native forwarding identity' do
    result = rails_probe(<<~RUBY)
      require './config/environment'
      require 'sidekiq/api'
      require 'json'
      ActiveJob::Base.queue_adapter = :sidekiq
      require './spec/support/phoenix_tables'
      Object.new.extend(PhoenixTables).phoenix_tables!
      db = ActiveRecord::Base.connection
      Sidekiq.redis { |r| r.call('FLUSHDB') }
      ENV['DAWARICH_CLOUD_DRAIN_ONLY'] = 'true'
      type = 'trips.calculate'
      key = 'command:' + type
      payload = { 'trip_id' => 991, 'distance_unit' => 'km' }
      options = { aggregate_id: '991', producer: 'drain-probe' }
      event = 'c87d611e-7182-4f54-8f0b-2b641debe4b4'
      db.transaction do
        db.execute("INSERT INTO phoenix.job_owners(key, owner) VALUES ('command:trips.calculate','oban') ON CONFLICT (key) DO UPDATE SET owner='oban'")
        before = JobOutbox.count
        root = begin; JobCommands.produce(type, payload, **options); 'acknowledged'; rescue StandardError => e; e.class.name; end
        forwarded = 2.times.map { JobCommands.produce(type, payload.merge('source_job_id' => event), **options) }
        rows = JobOutbox.where(event_id: event).to_a
        db.execute("UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='command:trips.calculate'")
        child = begin; JobCommands.produce(type, payload.merge('source_job_id' => event), **options); 'acknowledged'; rescue StandardError => e; e.class.name; end
        puts 'DRAIN_PROBE=' + JSON.generate(root: root, forwarded: forwarded, child: child,
          count_delta: JobOutbox.count - before, event: rows.map(&:event_id),
          source_ids: rows.map { |r| r.payload['source_job_id'] }, queued: Sidekiq::Queue.all.sum(&:size))
        raise ActiveRecord::Rollback
      end
      Sidekiq.redis { |r| r.call('FLUSHDB') }
    RUBY
    expect(result).to include('root' => 'CloudDrain::EnqueueRefused', 'forwarded' => %w[outbox outbox],
                              'child' => 'CloudDrain::EnqueueRefused', 'count_delta' => 1,
                              'event' => ['c87d611e-7182-4f54-8f0b-2b641debe4b4'],
                              'source_ids' => ['c87d611e-7182-4f54-8f0b-2b641debe4b4'], 'queued' => 0)
  end

  it 'native web boot runs migrate then seeds then Phoenix with original server argv' do
    result = run_script('web-entrypoint.sh', *server)
    expect(result[:status]).to be_success
    expect(result[:calls]).to eq([
                                   'dawarich migrate', 'dawarich seeds',
                                   'dawarich eval Dawarich.Release.halt_unless_ready()',
                                   'dawarich start bundle|exec|puma|-C|config/puma.rb|-p|5000|--tag|two words|'
                                 ])
  end

  it 'self-hosted native release runs migration and seeds without Rails tasks' do
    result = run_script('release.sh')
    expect(result[:status]).to be_success
    expect(result[:calls]).to eq(['dawarich migrate', 'dawarich seeds'])
    %w[STUB_MIGRATE_STATUS STUB_SEEDS_STATUS].each do |failure|
      result = run_script('release.sh', **{ failure => '7' })
      expect(result[:status].exitstatus).to eq(7)
      expected = failure == 'STUB_MIGRATE_STATUS' ? ['dawarich migrate'] : ['dawarich migrate', 'dawarich seeds']
      expect(result[:calls]).to eq(expected)
    end
  end

  it 'Cloud native lifecycle refuses before either migrator runs' do
    %w[release.sh web-entrypoint.sh].each do |script|
      result = run_script(script, *server, SELF_HOSTED: 'false')
      expect(result[:status]).not_to be_success
      expect(result[:stderr]).to include('requires self-hosted mode')
      expect(result[:calls]).to be_empty
    end
  end

  it 'native web boot stops on migration or seed failure' do
    [server, ['bin/rails', 'runner', 'puts 1']].each do |argv|
      %w[STUB_MIGRATE_STATUS STUB_SEEDS_STATUS].each do |failure|
        result = run_script('web-entrypoint.sh', *argv, **{ failure => '7' })
        expect(result[:status].exitstatus).to eq(7)
        expected = failure == 'STUB_MIGRATE_STATUS' ? ['dawarich migrate'] : ['dawarich migrate', 'dawarich seeds']
        expect(result[:calls]).to eq(expected)
      end
    end
    [nil, 'false'].each do |flag|
      expect(run_script('web-entrypoint.sh', *server, DAWARICH_PHOENIX_LIFECYCLE: flag)[:status]).to be_success
    end
    ['', 'yes', 'TRUE'].each do |flag|
      result = run_script('web-entrypoint.sh', *server, DAWARICH_PHOENIX_LIFECYCLE: flag)
      expect(result[:status]).not_to be_success
      expect(result[:calls]).to be_empty
    end
  end

  it 'native readiness failure never launches Rails' do
    %w[web-entrypoint.sh cloud-entrypoint.sh].each do |script|
      %w[1 3 4 5].each do |failure|
        result = run_script(script, *server, STUB_READY_STATUS: failure)
        expect(result[:status].exitstatus).to eq(failure.to_i)
        expect(result[:calls].last).to eq('dawarich eval Dawarich.Release.halt_unless_ready()')
        expect(result[:calls]).not_to include(a_string_starting_with('bundle '),
                                              a_string_starting_with('dawarich start'))
      end
    end
    %w[1 3 4 5].each do |failure|
      result = run_script('cloud-entrypoint.sh', *server, SELF_HOSTED: 'false', STUB_READY_STATUS: failure)
      expect(result[:status].exitstatus).to eq(failure.to_i)
      expect(result[:calls]).to eq(['dawarich eval Dawarich.Release.halt_unless_ready()'])
    end
  end

  it 'worker entrypoints retain real Sidekiq and never migrate or seed' do
    %w[sidekiq-entrypoint.sh cloud-sidekiq-entrypoint.sh].each do |script|
      result = run_script(script, 'sidekiq', '-C', 'config/sidekiq.yml')
      expect(result[:status]).to be_success
      expect(result[:calls]).to eq([if script == 'sidekiq-entrypoint.sh'
                                      'bundle exec sidekiq'
                                    else
                                      'bundle exec sidekiq -C config/sidekiq.yml'
                                    end])
    end
  end

  it 'off-mode keeps legacy boot and arbitrary command argv' do
    [nil, 'false'].each do |flag|
      [server, ['bin/rails', 'runner', 'puts 1']].each do |argv|
        result = run_script('web-entrypoint.sh', *argv, DAWARICH_PHOENIX_LIFECYCLE: flag)
        expect(result[:status]).to be_success
        expect(result[:calls].first(4)).to eq(['bundle exec rails db:migrate', 'bundle exec rake data:migrate',
                                               'bundle exec rails db:seed', 'dawarich eval Dawarich.Release.migrate()'])
        expected = if argv == server
                     'dawarich start bundle|exec|puma|-C|config/puma.rb|-p|5000|--tag|two words|'
                   else
                     'bundle exec bin/rails runner puts 1'
                   end
        expect(result[:calls].last).to eq(expected)
      end
    end
  end
end
