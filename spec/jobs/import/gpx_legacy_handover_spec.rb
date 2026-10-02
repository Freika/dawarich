# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::ProcessJob, type: :job do
  let!(:import) { create(:import, source: :gpx, skip_background_processing: true) }
  let(:job) { described_class.new }

  before do
    xml = '<gpx><trk><trkseg><trkpt lat="51" lon="13"><time>2026-01-01T10:00:00</time>' \
          '</trkpt></trkseg></trk></gpx>'
    import.file.attach(io: StringIO.new(xml), filename: 'legacy.gpx')
  end

  it 'forwards an old queued legacy job once when native ownership has since been claimed' do
    job_owner!('command:imports.process_gpx', :oban)
    Time.use_zone('Pacific/Auckland') { job.perform(import.id) }
    expect(import.points.count).to eq(0)
    row = JobOutbox.pending.sole
    expect(row.event_id).to eq(job.job_id)
    expect(row.payload).to eq('import_id' => import.id, 'user_id' => import.user_id,
                              'time_zone' => 'Pacific/Auckland')
    Time.use_zone('Pacific/Auckland') { job.perform(import.id) }
    expect(JobOutbox.count).to eq(1)
  end

  it 'does not restart a completed GPX import from a duplicate queued job' do
    import.update!(status: :completed)
    job.perform(import.id)
    expect(import.points.count).to eq(0)
  end

  it 'retries a busy GPX import ten times, then marks it failed with a clear message' do
    hold_import_lock("phoenix-import:#{import.id}") do
      perform_enqueued_jobs { described_class.perform_later(import.id) }
    end
    expect(performed_jobs.count { |entry| entry[:job] == described_class }).to eq(10)
    expect(import.reload).to have_attributes(status: 'failed', error_message: Imports::BusyRetry::MESSAGE)
    expect(import.points.count).to eq(0)
  end

  it 'leaves a GPX import that another attempt completed while this one waited' do
    import.update!(status: :completed)
    hold_import_lock("phoenix-import:#{import.id}") do
      perform_enqueued_jobs { described_class.perform_later(import.id) }
    end
    expect(import.reload).to have_attributes(status: 'completed', error_message: nil)
  end
end
