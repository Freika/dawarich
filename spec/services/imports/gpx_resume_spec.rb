# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports::GpxResume' do
  let!(:import) { create(:import, source: :gpx, skip_background_processing: true) }
  let(:event) { SecureRandom.uuid }
  let(:payload) do
    { 'event_id' => event, 'import_id' => import.id, 'user_id' => import.user_id,
                   'time_zone' => 'Pacific/Auckland' }
  end

  before do
    phoenix_tables!
    sql = <<~SQL.squish
      INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone)
      VALUES (?,?,?,?)
    SQL
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(
                                            [sql, event, import.id, import.user_id, 'Pacific/Auckland']
                                          ))
  end

  it 'resumes a real import in its captured zone and completes its receipt' do
    xml = <<~XML
      <gpx version="1.1"><trk><trkseg><trkpt lat="51" lon="13">
      <time>2026-01-01T10:00:00</time></trkpt></trkseg></trk></gpx>
    XML
    import.file.attach(io: StringIO.new(xml), filename: 'resume.gpx')
    Imports::GpxResume.perform(payload)
    expect(import.reload).to be_completed
    expect(import.points.count).to eq(1)
    expect(import.points.sole.timestamp).to eq(1_767_214_800)
    expect(state).to eq('completed')
    Imports::GpxResume.perform(payload)
    expect(import.points.count).to eq(1)
  end

  it 'forwards exactly once after Oban ownership is restored' do
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'resume.gpx')
    job_owner!('command:imports.process_gpx', :oban)
    Imports::GpxResume.perform(payload)
    row = JobOutbox.pending.sole
    expect(row.payload).to eq(payload.except('event_id'))
    expect(row.event_id).not_to eq(event)
    expect(state).to eq('forwarded')
    Imports::GpxResume.perform(payload)
    expect(JobOutbox.count).to eq(1)
  end

  it 'ignores an unrecorded event instead of creating a new import job' do
    Imports::GpxResume.perform(payload.merge('event_id' => SecureRandom.uuid))
    expect(import.reload).to be_created
    expect(JobOutbox.count).to eq(0)
    expect(state).to eq('pending')
  end

  it 'honours native admission fallback instead of forwarding it back to the rejected parser' do
    job_owner!('command:imports.process_gpx', :oban)
    query = 'UPDATE phoenix.import_handoffs SET native_fallback=true WHERE event_id=?'
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([query, event]))
    xml = '<gpx><trk><trkseg><trkpt lat="51" lon="13"><time>2026-01-01T10:00:00Z</time>' \
          '</trkpt></trkseg></trk></gpx>'
    import.file.attach(io: StringIO.new(xml), filename: 'legacy.gpx')
    Imports::GpxResume.perform(payload)
    expect(import.points.count).to eq(1)
    expect(JobOutbox.where(command_type: 'imports.process_gpx').count).to eq(0)
    expect(state).to eq('completed')
  end

  def state
    ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array(
                                                 ['SELECT state FROM phoenix.import_handoffs WHERE event_id=?', event]
                                               ))
  end

  it 'retries a busy resume ten times, then marks the import failed with a clear message' do
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'resume.gpx')
    hold_import_lock("import:#{import.id}") do
      perform_enqueued_jobs { Import::GpxResumeJob.perform_later(payload) }
    end
    expect(performed_jobs.count { |entry| entry[:job] == Import::GpxResumeJob }).to eq(10)
    expect(import.reload).to have_attributes(status: 'failed', error_message: Imports::BusyRetry::MESSAGE)
    expect(state).to eq('pending')
  end
end
