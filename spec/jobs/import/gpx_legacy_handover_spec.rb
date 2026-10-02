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

  it 'uses the shared per-import session lock before starting legacy processing' do
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      connection = PG.connect(host: config[:host], port: config[:port], user: config[:username],
                              password: config[:password], dbname: config[:database])
      key = "phoenix-import:#{import.id}"
      begin
        connection.exec_params('SELECT pg_advisory_lock(hashtextextended($1,0))', [key])
        ready.push(true)
        release.pop
        connection.exec_params('SELECT pg_advisory_unlock(hashtextextended($1,0))', [key])
      ensure
        connection.finish
      end
    end
    ready.pop
    expect { job.perform(import.id) }.to raise_error(Imports::GpxLegacy::Busy)
    expect(import.points.count).to eq(0)
  ensure
    release.push(true)
    holder&.join
  end
end
