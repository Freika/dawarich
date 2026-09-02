# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::SyncJob, type: :job do
  it 'syncs the requested user' do
    user = create(:user)
    sync = instance_double(TeslaMate::Sync, call: { points: 0 })
    allow(TeslaMate::Sync).to receive(:new).with(user).and_return(sync)

    described_class.perform_now(user.id)

    expect(sync).to have_received(:call)
  end

  it 'no-ops for a missing user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it 'retries an incomplete sync without notifying on the first failure' do
    user = create(:user)
    sync = instance_double(TeslaMate::Sync)
    allow(sync).to receive(:call).and_raise(TeslaMate::Sync::IncompleteError, 'drive 42 failed')
    allow(TeslaMate::Sync).to receive(:new).with(user).and_return(sync)
    allow(ExceptionReporter).to receive(:call)

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(described_class).with(user.id)

    expect(user.notifications).to be_empty
    expect(ExceptionReporter).not_to have_received(:call)
  end

  it 'notifies and reports only after the bounded retries are exhausted' do
    user = create(:user)
    sync = instance_double(TeslaMate::Sync)
    allow(sync).to receive(:call).and_raise(TeslaMate::Sync::IncompleteError, 'drive 42 failed')
    allow(TeslaMate::Sync).to receive(:new).with(user).and_return(sync)
    allow(ExceptionReporter).to receive(:call)
    job = described_class.new(user.id)
    job.exception_executions = { '[TeslaMate::Client::Error]' => 2 }

    expect { job.perform_now }.not_to have_enqueued_job(described_class)

    expect(user.notifications.last.content).to include('drive 42 failed')
    expect(ExceptionReporter).to have_received(:call)
      .with(instance_of(TeslaMate::Sync::IncompleteError), "TeslaMateApi sync failed for user #{user.id}")
  end

  it 'does not start a second sync while one already holds the user lock' do
    user = create(:user)
    allow(ActiveRecord::Base).to receive(:with_advisory_lock)
      .with("teslamate-sync:#{user.id}", timeout_seconds: 0).and_return(false)

    expect(TeslaMate::Sync).not_to receive(:new)

    described_class.perform_now(user.id)
  end

  it 'disables Sidekiq retries outside the three Active Job attempts' do
    expect(described_class.get_sidekiq_options['retry']).to be(false)
  end
end
