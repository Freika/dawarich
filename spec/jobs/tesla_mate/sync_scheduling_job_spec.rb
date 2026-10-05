# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::SyncSchedulingJob, type: :job do
  it 'skips Rails scheduling while the cron belongs to Oban' do
    create(:user, settings: { 'teslamate_url' => 'https://teslamate.example' })
    job_owner!('cron:teslamate_sync_job', :oban)
    expect { described_class.perform_now }.not_to have_enqueued_job(TeslaMate::SyncJob)
  end

  it 'enqueues one sync for every user with a TeslaMateApi URL' do
    configured = create(:user).tap do |user|
      user.update!(settings: user.settings.merge('teslamate_url' => 'https://teslamate.example'))
    end
    create(:user)

    expect { described_class.perform_now }
      .to have_enqueued_job(TeslaMate::SyncJob).with(configured.id).exactly(:once)
  end

  it 'skips blank TeslaMateApi URLs' do
    create(:user).tap { |user| user.update!(settings: user.settings.merge('teslamate_url' => '')) }

    expect { described_class.perform_now }.not_to have_enqueued_job(TeslaMate::SyncJob)
  end
  it 'TeslaMate fences manual and marked sweeps and shares slot receipts with native scheduling' do
    user = create(:user, status: :inactive, settings: { 'teslamate_url' => 'https://a.example' })
    key = 'cron:teslamate_sync_job'
    job_owner!(key, :oban)
    expect { described_class.perform_now }.not_to have_enqueued_job
    expect { described_class.perform_now('a12d2_cron') }.not_to have_enqueued_job
    job_owner!(key, :sidekiq)
    job = described_class.new('a12d2_cron')
    job.enqueued_at = Time.zone.at(1_759_050_000)
    commands = Integrations::SchedulingCommands
    ActiveRecord::Base.transaction { commands.claim('teslamate', 1_759_050_000, user.id) }
    expect { job.perform('a12d2_cron') }.not_to have_enqueued_job
    job.enqueued_at += 60
    expect { job.perform('a12d2_cron') }
      .to have_enqueued_job(TeslaMate::SyncJob).with(user.id).exactly(:once)
    clear_enqueued_jobs
    expect { job.perform('a12d2_cron') }.not_to have_enqueued_job
    expect { described_class.perform_now('invalid') }.to raise_error(ArgumentError)
  end
end
