# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'dawarich:jobs' do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('dawarich:jobs:release') }

  after do
    %w[release unpin rehome status drain_status].each { |task| Rake::Task["dawarich:jobs:#{task}"].reenable }
  end

  def run(task, *args)
    Rake::Task[task].reenable
    expect { Rake::Task[task].invoke(*args) }.to output.to_stdout
  end

  it 'restored source cron controls produce one batch after pinned rollback' do
    phoenix_tables!
    user = create(:user, settings: { 'teslamate_url' => 'https://teslamate.example.invalid' })
    key = 'cron:teslamate_sync_job'
    name = "impl-a12d3-resume-#{SecureRandom.uuid}"
    config = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('teslamate_sync_job')
    expect(Sidekiq::Cron::Job.load_from_hash(name => config.merge('status' => 'disabled'))).to eq({})
    cron = Sidekiq::Cron::Job.find(name)
    at = cron.send(:parsed_cron).next_time(Time.utc(2026, 10, 24, 12)).to_t.utc + 1
    job_owner!(key, :oban)
    expect { cron.test_and_enqueue_for_time!(at) }.not_to have_enqueued_job
    run('dawarich:jobs:release', key)
    expect(ActiveRecord::Base.connection.select_rows(
             "SELECT owner, pinned FROM phoenix.job_owners WHERE key = 'cron:teslamate_sync_job'"
           )).to eq([['sidekiq', true]])
    cron.enable!
    restored = Sidekiq::Cron::Job.find(name)
    expect { 2.times { restored.test_and_enqueue_for_time!(at) } }
      .to have_enqueued_job(TeslaMate::SyncSchedulingJob).exactly(:once)
    expect(restored.enabled?).to be(true)
    request = enqueued_jobs.sole.deep_dup
    job = ActiveJob::Base.deserialize(request)
    job.enqueued_at = at
    expect { 2.times { job.perform_now } }.to have_enqueued_job(TeslaMate::SyncJob).with(user.id).exactly(:once)
  ensure
    Sidekiq::Cron::Job.find(name)&.destroy if name
  end

  it 'releases a key to Sidekiq, pinned, and unpins it' do
    job_owner!('cron:app_version_checking_job', :oban)

    run('dawarich:jobs:release', 'cron:app_version_checking_job')
    expect(JobOwnership.with_owner('cron:app_version_checking_job') { :sidekiq_runs }).to eq(:sidekiq_runs)

    run('dawarich:jobs:unpin', 'cron:app_version_checking_job')
    expect(ActiveRecord::Base.connection.select_value(
             "SELECT pinned FROM phoenix.job_owners WHERE key = 'cron:app_version_checking_job'"
           )).to be(false)
  end

  it 'exits 1 with a usage message when release is given a blank key' do
    Rake::Task['dawarich:jobs:release'].reenable

    expect do
      expect { Rake::Task['dawarich:jobs:release'].invoke('') }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end.to output(%r{usage: bin/rails "dawarich:jobs:release\[<key>\]"}).to_stderr
  end

  it 'exits 1 with a usage message when unpin is given a blank key' do
    Rake::Task['dawarich:jobs:unpin'].reenable

    expect do
      expect { Rake::Task['dawarich:jobs:unpin'].invoke('') }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end.to output(%r{usage: bin/rails "dawarich:jobs:unpin\[<key>\]"}).to_stderr
  end

  it 'releases and unpins an unknown key without raising, upserting a fresh pinned row' do
    phoenix_tables!

    run('dawarich:jobs:release', 'command:no.such.job')
    expect(ActiveRecord::Base.connection.select_rows(
             "SELECT owner, pinned FROM phoenix.job_owners WHERE key = 'command:no.such.job'"
           )).to eq([['sidekiq', true]])

    run('dawarich:jobs:unpin', 'command:no.such.job')
    expect(ActiveRecord::Base.connection.select_value(
             "SELECT pinned FROM phoenix.job_owners WHERE key = 'command:no.such.job'"
           )).to be(false)
  end

  it 'propagates a RuntimeError from release when Phoenix has never migrated the database' do
    ActiveRecord::Base.connection.execute('DROP TABLE phoenix.job_owners')
    PhoenixSchema.reset!
    Rake::Task['dawarich:jobs:release'].reenable

    expect { Rake::Task['dawarich:jobs:release'].invoke('cron:app_version_checking_job') }
      .to raise_error(RuntimeError, /phoenix\.job_owners does not exist/)
  end

  it 're-homes the pending commands of a key' do
    job_owner!('command:trips.calculate', :oban)
    JobCommands.produce('trips.calculate', { 'trip_id' => 9, 'distance_unit' => 'mi' },
                        aggregate_id: 9, dedupe_key: '9', producer: 'spec')

    expect { run('dawarich:jobs:rehome', 'command:trips.calculate') }
      .to have_enqueued_job(Trips::CalculateAllJob).with(9, 'mi')
    expect(JobOutbox.count).to eq(0)
    expect(JobOwnership.with_owner('command:trips.calculate') { :sidekiq_runs }).to eq(:sidekiq_runs)
  end

  it 're-homing the archival mail key names the Lite cron key it releases with it' do
    job_owner!('cron:lite_archival_warning_job', :oban)
    job_owner!('command:mail.user.archival_approaching', :oban)

    Rake::Task['dawarich:jobs:rehome'].reenable

    expect { Rake::Task['dawarich:jobs:rehome'].invoke('command:mail.user.archival_approaching') }
      .to output(/cron:lite_archival_warning_job: sidekiq \(pinned\)/).to_stdout
  end

  it 'reports commands left in Phoenix and the rollback wait condition' do
    allow(JobCommands).to receive(:rehome!).and_return({ moved: 2, left: 1 })
    Rake::Task['dawarich:jobs:rehome'].reenable
    expected_output = Regexp.new(
      [
        '2 command\\(s\\) re-homed to Sidekiq, 1 command\\(s\\) left in Phoenix',
        'will finish in Phoenix.*dawarich:jobs:status.*no pending commands',
        'no incomplete Oban jobs.*before rolling back'
      ].join('.*'), Regexp::MULTILINE
    )

    expect { Rake::Task['dawarich:jobs:rehome'].invoke('command:trips.calculate') }
      .to output(expected_output).to_stdout
    expect(JobCommands).to have_received(:rehome!).with('trips.calculate', by: JobOwnership.operator)
  end

  it 'reports what moved and what is left when a Sidekiq enqueue stops the re-home, and exits 1' do
    allow(JobCommands).to receive(:rehome!)
      .and_return({ moved: 1, left: 2, error: 'RedisClient::CannotConnectError' })
    Rake::Task['dawarich:jobs:rehome'].reenable

    reported = output(/1 command\(s\) re-homed to Sidekiq, 2 command\(s\) left in Phoenix/).to_stdout
    stopped = output(/RedisClient::CannotConnectError.*dawarich:jobs:rehome\[command:exports\.points\].*again/m).to_stderr

    expect do
      expect { Rake::Task['dawarich:jobs:rehome'].invoke('command:exports.points') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to reported.and(stopped)
  end

  it 'fails with a clear message when the owner row stays locked by another transaction' do
    allow(JobOwnership).to receive(:release!).and_raise(ActiveRecord::LockWaitTimeout)
    allow(JobOwnership).to receive(:unpin!).and_raise(ActiveRecord::LockWaitTimeout)
    allow(JobCommands).to receive(:rehome!).and_raise(ActiveRecord::LockWaitTimeout)

    { 'release' => 'cron:app_version_checking_job', 'unpin' => 'cron:app_version_checking_job',
      'rehome' => 'command:exports.points' }.each do |task, key|
      Rake::Task["dawarich:jobs:#{task}"].reenable

      expect do
        expect { Rake::Task["dawarich:jobs:#{task}"].invoke(key) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/#{Regexp.escape(key)}: .*locked by another transaction.*Nothing changed/m).to_stderr
    end
  end

  it 'releases the Lite archival cron together with its mail key and says so' do
    job_owner!('cron:lite_archival_warning_job', :oban)
    job_owner!('command:mail.user.archival_approaching', :oban)
    Rake::Task['dawarich:jobs:release'].reenable

    expect { Rake::Task['dawarich:jobs:release'].invoke('cron:lite_archival_warning_job') }
      .to output(/command:mail\.user\.archival_approaching: sidekiq \(pinned\).*cron:lite_archival_warning_job: /m)
      .to_stdout
  end

  it 'prints the redacted drain observation from the installed task' do
    expect { Rake::Task['dawarich:jobs:drain_status'].invoke }
      .to output(/"status":.*"(?:BLOCKED|OBSERVED_EMPTY)".*"observation": true/m).to_stdout
  end

  it 'prints the health summary and gauges' do
    job_owner!('command:trips.calculate', :oban)

    Rake::Task['dawarich:jobs:status'].reenable
    expect { Rake::Task['dawarich:jobs:status'].invoke }.to output(/"alarm": true.*command:trips.calculate/m).to_stdout
  end
end
