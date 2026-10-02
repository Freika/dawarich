# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX reverse command dispatch' do
  let!(:import) { create(:import, source: :gpx, skip_background_processing: true) }

  it 'routes the persisted counter handoff through the current canonical owner' do
    job_owner!('command:imports.update_points_count', :oban)
    RailsCommands::Registry.handler('imports.postprocessing_step').call(
      'import_id' => import.id, 'user_id' => import.user_id, 'locale' => 'de',
      'time_zone' => 'Europe/Berlin', 'step' => 'command', 'command_type' => 'imports.update_points_count',
      'command_payload' => { 'import_id' => import.id }, 'aggregate_id' => import.id
    )
    expect(JobOutbox.pending.sole.payload).to eq('import_id' => import.id)
  end

  it 'schedules the owner-scoped receipt continuation through the reverse registry' do
    phoenix_tables!
    event = SecureRandom.uuid
    payload = { 'event_id' => event, 'import_id' => import.id, 'user_id' => import.user_id,
                'time_zone' => 'Europe/Berlin' }
    sql = 'INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone) VALUES (?,?,?,?)'
    values = [event, import.id, import.user_id, 'Europe/Berlin']
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, *values]))
    expect { RailsCommands::Registry.handler('imports.resume').call(payload) }
      .to have_enqueued_job(Import::GpxResumeJob).with(payload)
  end

  it 'dispatches anomaly stats in the captured zone and custom queue' do
    payload = { 'user_id' => import.user_id, 'year' => 2026, 'month' => 1,
                'time_zone' => 'Pacific/Auckland', 'job_queue' => 'low_priority' }
    expect { RailsCommands::Registry.handler('points.anomaly_stats').call(payload) }
      .to have_enqueued_job(Stats::CalculatingJob).with(import.user_id, 2026, 1).on_queue('low_priority')
  end

  %w[extract remove].each do |action|
    it "dispatches the current native manual #{action} through the merged reverse registry" do
      import.file.attach(io: File.open(Rails.root.join('spec/fixtures/files/gpx/gpx_single_waypoint.gpx')),
                         filename: 'manual.gpx', content_type: 'application/gpx+xml')
      event = SecureRandom.uuid
      stamp = Time.current.iso8601(6)
      import.update_columns(status: 1, additional_data_extraction_status: action == 'extract' ? 1 : 2,
                            additional_data_extraction: { 'phoenix_extraction_event' => event,
                              'phoenix_extraction_action' => action, 'started_at' => stamp,
                              'options' => { 'trust_source' => false } })
      point = create(:point, user: import.user, import_id: import.id)
      place = create(:place, user: import.user, import_id: import.id) if action == 'remove'
      payload = { 'import_id' => import.id, 'user_id' => import.user_id, 'source' => Import.sources.fetch('gpx'),
                  'source_blob_id' => import.file.blob_id, 'event_id' => event, 'started_at' => stamp,
                  'time_zone' => 'Pacific/Auckland', 'locale' => 'fr' }
      kind = action == 'extract' ? 'imports.extraction_requested' : 'imports.extraction_destroy_requested'

      RailsCommands::Registry.handler(kind).call(payload)
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
      expect(job.fetch('timezone')).to eq('Pacific/Auckland')
      expect(job.fetch('locale')).to eq('fr')
      ActiveJob::Base.execute(job)
      expect(Point.exists?(point.id)).to be(true)
      if action == 'extract'
        expect(import.reload.additional_data_extraction_status).to eq('completed')
        expect(Place.where(import_id: import.id, user_id: import.user_id).count).to eq(1)
      else
        expect(Place.exists?(place.id)).to be(false)
        expect(import.reload.additional_data_extraction_status).to eq('not_attempted')
      end
    end
  end
end
