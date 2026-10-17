# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native manual extraction commands' do
  let(:user) { create(:user, settings: { 'locale' => 'fr' }) }
  let(:import) { create(:import, user:, source: :gpx, status: :processing, skip_background_processing: true) }
  let(:stamp) { Time.current.iso8601(6) }
  let(:event) { SecureRandom.uuid }
  let(:payload) do
    { 'import_id' => import.id, 'user_id' => user.id, 'source' => Import.sources.fetch('gpx'),
      'source_blob_id' => import.file.blob_id, 'event_id' => event, 'started_at' => stamp,
      'time_zone' => 'Pacific/Auckland', 'locale' => 'fr' }
  end

  before do
    import.file.attach(io: File.open(Rails.root.join('spec/fixtures/files/gpx/gpx_single_waypoint.gpx')),
                       filename: 'manual.gpx', content_type: 'application/gpx+xml')
  end

  def request!(action)
    import.update_columns(additional_data_extraction_status: action == 'extract' ? 1 : 2,
                          additional_data_extraction: { 'phoenix_extraction_event' => event,
                            'phoenix_extraction_action' => action, 'started_at' => stamp,
                            'options' => { 'trust_source' => false } })
    kind = action == 'extract' ? 'imports.extraction_requested' : 'imports.extraction_destroy_requested'
    Imports::ExtractionCommands::HANDLERS.fetch(kind).fetch(:call).call(payload)
    ActiveJob::Base.queue_adapter.enqueued_jobs.last
  end

  it 'runs the real extractor for a processing import in captured locale and zone' do
    job = request!('extract')
    expect(job.fetch(:job)).to eq(EnhancedImport::ExtractJob)
    expect(job.fetch('timezone')).to eq('Pacific/Auckland')
    expect(job.fetch('locale')).to eq('fr')
    ActiveJob::Base.execute(job)
    expect(import.reload.additional_data_extraction_status).to eq('completed')
    expect(import.extraction_counts[:places]).to eq(1)
    expect(Place.where(import_id: import.id, user_id: user.id).count).to eq(1)
    expect(import.additional_data_extraction.dig('options', 'trust_source')).to be(false)
  end

  it 'runs the real remover while retaining raw points' do
    place = create(:place, user:, import_id: import.id)
    point = create(:point, user:, import_id: import.id)
    job = request!('remove')
    expect(job.fetch(:job)).to eq(EnhancedImport::DestroyJob)
    ActiveJob::Base.execute(job)
    expect(Place.exists?(place.id)).to be(false)
    expect(Point.exists?(point.id)).to be(true)
    expect(import.reload.additional_data_extraction_status).to eq('not_attempted')
    expect(import.additional_data_extraction).to eq({})
  end

  it 'refuses delayed source, blob, run, timestamp and actor changes before either real job' do
    %w[extract remove].each do |action|
      job = request!(action)
      original = import.attributes.slice('user_id', 'source', 'additional_data_extraction')
      mutations = [
        { user_id: create(:user).id }, { source: Import.sources.fetch('google_phone_takeout') },
        { additional_data_extraction: import.additional_data_extraction.merge(
          'phoenix_extraction_event' => SecureRandom.uuid
        ) },
        { additional_data_extraction: import.additional_data_extraction.merge('started_at' => 1.hour.ago.iso8601) }
      ]
      mutations.each do |mutation|
        import.update_columns(mutation)
        expect { ActiveJob::Base.execute(job) }.not_to(change { Place.count })
        expect(import.reload.additional_data_extraction_status).to eq(action == 'extract' ? 'pending' : 'running')
        import.update_columns(original)
      end
      attachment = import.file_attachment
      attachment.update_columns(name: 'elsewhere')
      expect { ActiveJob::Base.execute(job) }.not_to(change { Place.count })
      attachment.update_columns(name: 'file')
      user.update_columns(deleted_at: Time.current)
      expect { ActiveJob::Base.execute(job) }.not_to(change { Place.count })
      user.update_columns(deleted_at: nil)
    end
  end

  it 'rejects changed identity before enqueueing the delayed command' do
    request!('extract')
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    import.update_columns(user_id: create(:user).id)
    expect { Imports::ExtractionCommands.call(payload, 'extract') }.not_to have_enqueued_job
  end

  it 'retains the actor and new timestamp when a real storage write retries' do
    job = request!('extract')
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE FUNCTION reject_native_extraction_place() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'native extraction write unavailable'; END $$
    SQL
    connection.execute(<<~SQL)
      CREATE TRIGGER reject_native_extraction_place BEFORE INSERT ON places
      FOR EACH ROW EXECUTE FUNCTION reject_native_extraction_place()
    SQL
    begin
      ActiveJob::Base.execute(job)
      retry_job = ActiveJob::Base.queue_adapter.enqueued_jobs.reverse.find { |j| j[:job] == EnhancedImport::ExtractJob }
      expected = ActiveJob::Arguments.deserialize(retry_job.fetch('arguments')).last.fetch(:expected)
      expect(expected.fetch('user_id')).to eq(user.id)
      expect(expected.fetch('event_id')).to eq(event)
      expect(expected.fetch('started_at')).to eq(import.reload.additional_data_extraction.fetch('started_at'))
      expect(import.additional_data_extraction_status).to eq('pending')
    ensure
      connection.execute('DROP TRIGGER reject_native_extraction_place ON places')
      connection.execute('DROP FUNCTION reject_native_extraction_place()')
    end
    ActiveJob::Base.execute(retry_job)
    expect(import.reload.additional_data_extraction_status).to eq('completed')
    expect(Place.where(user_id: user.id, import_id: import.id).count).to eq(1)
  end

  it 'does not report an exhausted native failure onto a changed actor' do
    queued = request!('extract')
    arguments = ActiveJob::Arguments.deserialize(queued.fetch('arguments'))
    job = EnhancedImport::ExtractJob.new(*arguments)
    import.update_columns(user_id: create(:user).id)
    job.fail_after_retries(StandardError.new('obsolete failure'))
    expect(import.reload.additional_data_extraction_status).to eq('pending')
    expect(import.additional_data_extraction['error_message']).to be_nil
  end
end
