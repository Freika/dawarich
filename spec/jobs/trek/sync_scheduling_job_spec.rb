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
    key = 'cron:trek_sync_job'
    job_owner!(key, :oban)
    expect { described_class.perform_now }.not_to have_enqueued_job
    expect { described_class.perform_now('a12d2_cron') }.not_to have_enqueued_job
    job_owner!(key, :sidekiq)
    expect { described_class.perform_now('a12d2_cron') }
      .to have_enqueued_job(Trek::SyncJob).with(source.id).exactly(:once)
    clear_enqueued_jobs
    expect { described_class.perform_now('a12d2_cron') }.not_to have_enqueued_job
    expect { described_class.perform_now('invalid') }.to raise_error(ArgumentError)
  end
end
