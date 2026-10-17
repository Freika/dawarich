# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trek command producers' do
  before { stub_host_addresses('trek.example.test', '93.184.216.34') }

  it 'queues selection and sync after commit with exact cursor arguments' do
    source = create(:trip_source)
    clear_enqueued_jobs
    import = { 'source_id' => source.id, 'identifiers' => ['12'], 'selection_token' => 'token', 'offset' => 100 }
    sync = { 'source_id' => source.id, 'after_id' => 123 }
    ActiveRecord::Base.transaction do
      expect(JobCommands.produce('imports.trek_import', import, aggregate_id: source.id, producer: 'spec'))
        .to eq(:sidekiq)
      expect(JobCommands.produce('imports.trek_sync', sync, aggregate_id: source.id, producer: 'spec'))
        .to eq(:sidekiq)
      expect(enqueued_jobs).to be_empty
    end
    expect(Trek::ImportTripsJob).to have_been_enqueued.with(source.id, ['12'], 'token', 100).exactly(:once)
    expect(Trek::SyncJob).to have_been_enqueued.with(source.id, 123).exactly(:once)
    job_owner!('command:imports.trek_sync', :oban)
    job = Trek::SyncJob.new(source.id, 123)
    allow(Trek::Sync).to receive(:new) { raise 'provider executed without admitted owner' }
    2.times { job.perform_now }
    expect(JobOutbox.pending.pluck(:event_id, :command_type, :payload))
      .to eq([[job.job_id, 'imports.trek_sync', sync]])
    job_owner!('command:imports.trek_import', :oban)
    ActiveRecord::Base.transaction do
      expect(Imports::TrekCommands.select(source, ['12'])).to be_present
      expect(JobOutbox.pending.where(command_type: 'imports.trek_import').count).to eq(1)
      raise ActiveRecord::Rollback
    end
    expect(source.reload).not_to be_importing
    expect(JobOutbox.pending.where(command_type: 'imports.trek_import')).to be_empty
    token = Imports::TrekCommands.select(source, ['12'])
    expect(JobOutbox.pending.where(command_type: 'imports.trek_import').pluck(:payload))
      .to eq([{ 'source_id' => source.id, 'identifiers' => ['12'], 'selection_token' => token, 'offset' => 0 }])
    expect(source.reload).to be_importing
  end
end
