# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::SyncSchedulingJob, type: :job do
  before do
    stub_host_addresses('trek.example.test', '93.184.216.34')
  end

  it 'skips Rails scheduling while the Trek cron belongs to Oban' do
    create(:trip_source)
    job_owner!('cron:trek_sync_job', :oban)
    expect { described_class.perform_now }.not_to have_enqueued_job(Trek::SyncJob)
  end

  it 'enqueues one job for each active TREK source' do
    active = create(:trip_source)
    create(:trip_source, status: :disabled)

    expect { described_class.perform_now }
      .to have_enqueued_job(Trek::SyncJob).with(active.id).exactly(:once)
  end
  it 'Trek fences manual and marked sweeps and publishes a slot only once' do
    source = create(:trip_source)
    scheduled = described_class.new('a12d2_cron')
    scheduled.enqueued_at = Time.utc(2026, 10, 4, 12)
    key = 'cron:trek_sync_job'
    job_owner!(key, :oban)
    expect { described_class.perform_now }.not_to have_enqueued_job
    expect { scheduled.perform_now }.not_to have_enqueued_job
    job_owner!(key, :sidekiq)
    expect { scheduled.perform_now }
      .to have_enqueued_job(Trek::SyncJob).with(source.id).exactly(:once)
    clear_enqueued_jobs
    expect { scheduled.perform_now }.not_to have_enqueued_job
    expect { described_class.perform_now('invalid') }.to raise_error(ArgumentError)
    job_owner!('command:imports.trek_sync', :oban)
    allow(PhoenixLease).to receive(:try_hold).with("trek-sync:#{source.id}").and_return(false)

    [nil, 123].each do |cursor|
      args = cursor.nil? ? [source.id] : [source.id, cursor]
      accepted = Trek::SyncJob.new(*args)
      2.times { accepted.perform_now }
      row = JobOutbox.find_by!(event_id: accepted.job_id)
      expect(row.command_type).to eq('imports.trek_sync')
      expect(row.payload).to eq({ 'source_id' => source.id, 'after_id' => cursor })
      expect(row.aggregate_id).to eq(source.id)
      expect(JobOutbox.where(event_id: accepted.job_id).count).to eq(1)
    end
  end
end
