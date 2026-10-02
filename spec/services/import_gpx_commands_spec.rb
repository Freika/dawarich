# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImportCommands do
  let!(:user) { create(:user) }
  let!(:import) { create(:import, user:, source: :gpx, skip_background_processing: true) }

  before do
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'sample.gpx', content_type: 'application/gpx+xml')
    clear_enqueued_jobs
  end

  it 'captures the producing Rails time zone in the native command' do
    job_owner!('command:imports.process_gpx', :oban)
    Time.use_zone('Pacific/Auckland') { described_class.process(import, producer: 'spec') }
    expect(JobOutbox.pending.sole).to have_attributes(
      command_type: 'imports.process_gpx', command_version: 1,
      payload: { 'import_id' => import.id, 'user_id' => user.id, 'time_zone' => 'Pacific/Auckland' }
    )
    expect(Import::ProcessJob).not_to have_been_enqueued
  end

  it 'keeps the legacy job when Sidekiq owns processing' do
    expect { described_class.process(import, producer: 'spec') }
      .to have_enqueued_job(Import::ProcessJob).with(import.id)
    expect(JobOutbox.pending.count).to eq(0)
  end

  it 'keeps archives and sources without native admission on Rails' do
    job_owner!('command:imports.process_gpx', :oban)
    import.file.attach(io: StringIO.new('zip'), filename: 'sample.zip')
    expect { described_class.process(import, producer: 'spec') }
      .to have_enqueued_job(Import::ProcessJob).with(import.id)
    clear_enqueued_jobs
    import.update!(source: nil)
    expect { described_class.process(import, producer: 'spec') }
      .to have_enqueued_job(Import::ProcessJob).with(import.id)
    expect(JobOutbox.pending.count).to eq(0)
  end

  it 'does not enqueue the legacy job if the producing transaction rolls back' do
    ActiveRecord::Base.transaction do
      described_class.process(import, producer: 'spec')
      raise ActiveRecord::Rollback
    end
    expect(Import::ProcessJob).not_to have_been_enqueued
  end
end
