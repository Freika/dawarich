# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports::ProcessCommands' do
  let!(:import) { create(:import, source: :csv, skip_background_processing: true) }
  let(:payload) { { 'import_id' => import.id, 'user_id' => import.user_id, 'time_zone' => 'Europe/Berlin' } }
  let(:event) { SecureRandom.uuid }

  before do
    import.file.attach(io: StringIO.new("latitude,longitude,timestamp\n51.3,12.4,1768519800\n"), filename: 'normal.csv')
  end

  it 'produces a captured normal command and preserves the default Sidekiq route' do
    expect { ImportCommands.process(import, producer: 'spec') }.to have_enqueued_job(Import::ProcessJob).with(import.id)
    job_owner!('command:imports.process_normal', :oban)
    Time.use_zone('Europe/Berlin') { expect(ImportCommands.process(import, producer: 'spec')).to eq(:outbox) }
    Time.use_zone('Europe/Berlin') { ImportCommands.process(import, producer: 'spec') }
    expect(JobOutbox.pending.sole).to have_attributes(command_type: 'imports.process_normal', command_version: 1,
                                                      payload:, dedupe_key: "process-normal:#{import.id}")
    import.user.update!(settings: { 'timezone' => 'Pacific/Auckland' })
    expect(JobOutbox.pending.sole.payload).to eq(payload)
  end

  it 'keeps the pending normal command until a successful Sidekiq push in its captured zone' do
    job_owner!('command:imports.process_normal', :oban)
    Time.use_zone('Europe/Berlin') { ImportCommands.process(import, producer: 'spec') }
    allow(Import::ProcessJob.queue_adapter).to receive(:enqueue).and_raise(RedisClient::CannotConnectError,
                                                                           'redis down')
    expect(JobCommands.rehome!('imports.process_normal', by: 'spec'))
      .to eq({ moved: 0, left: 1, error: 'RedisClient::CannotConnectError' })
    expect(JobOutbox.pending.sole.payload).to eq(payload)
    allow(Import::ProcessJob.queue_adapter).to receive(:enqueue).and_call_original
    Time.use_zone('UTC') do
      expect { JobCommands.rehome!('imports.process_normal', by: 'spec') }
        .to have_enqueued_job(Import::ProcessJob).with(import.id)
    end
    expect(enqueued_jobs.last['timezone']).to eq('Europe/Berlin')
    expect(enqueued_jobs.last[:at]).to be_nil
    expect(enqueued_jobs.last[:job]).to eq(Import::ProcessJob)
    expect(JobOutbox.pending.count).to eq(0)
  end

  it 'forwards old normal jobs with their original identity and captured context' do
    job_owner!('command:imports.process_normal', :oban)
    job = Import::ProcessJob.new(import.id)
    job.job_id = event
    Time.use_zone('Europe/Berlin') { job.perform_now }
    expect(import.reload).to be_created
    expect(JobOutbox.pending.sole).to have_attributes(event_id: event, payload:)
    expect(JobOutbox.pending.sole.metadata['producer']).to eq('Import::ProcessJob')

    stale_import = Import.find(import.id)
    import.file.attach(io: StringIO.new('<gpx></gpx>'), filename: 'changed.gpx')
    Import.where(id: import.id).update_all(source: Import.sources.fetch('gpx'))
    JobOutbox.pending.delete_all
    job_owner!('command:imports.process_normal', :sidekiq)
    job_owner!('command:imports.process_gpx', :oban)
    Time.use_zone('Europe/Berlin') { Imports::NormalLegacy.perform(stale_import, event_id: event) }
    expect(import.reload).to be_created
    expect(JobOutbox.pending.sole).to have_attributes(command_type: 'imports.process_gpx', event_id: event, payload:)
  end

  it 'resumes the recorded normal event once and rejects another user or unrecorded event' do
    phoenix_tables!
    sql = 'INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone,native_fallback) ' \
          'VALUES(?,?,?,?,true)'
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, event, import.id, import.user_id,
                                                                                 'Europe/Berlin']))
    resume = payload.merge('event_id' => event)
    Imports::NormalResume.perform(resume.merge('user_id' => create(:user).id))
    Imports::NormalResume.perform(resume.merge('event_id' => SecureRandom.uuid))
    expect(import.reload).to be_created
    job_owner!('command:imports.process_normal', :oban)
    Time.use_zone('UTC') { Imports::NormalResume.perform(resume) }
    expect(import.reload).to be_completed
    expect(import.points.count).to eq(1)
    Imports::NormalResume.perform(resume)
    expect(import.points.count).to eq(1)
    expect(JobOutbox.where(command_type: 'imports.process_normal').count).to eq(0)
    state_sql = "SELECT state FROM phoenix.import_handoffs WHERE event_id='#{event}'"
    expect(ActiveRecord::Base.connection.select_value(state_sql)).to eq('completed')

    import.file.attach(io: StringIO.new('<gpx></gpx>'), filename: 'normal.gpx')
    import.update!(source: :gpx, status: :created)
    next_event = SecureRandom.uuid
    receipt_values = [sql.sub('true', 'false'), next_event, import.id, import.user_id, 'Europe/Berlin']
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(receipt_values))
    job_owner!('command:imports.process_gpx', :oban)
    Imports::NormalResume.perform(payload.merge('event_id' => next_event))
    expect(import.reload).to be_created
    expect(JobOutbox.pending.sole).to have_attributes(command_type: 'imports.process_gpx', payload:)
  end
end
