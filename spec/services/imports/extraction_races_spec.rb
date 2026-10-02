# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native extraction effects after concurrent import changes' do
  self.use_transactional_tests = false

  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:import) { create(:import, user:, source: :gpx, status: :processing, skip_background_processing: true) }
  let(:event) { SecureRandom.uuid }
  let(:started) { Time.current.iso8601(6) }
  let(:expected) do
    { 'user_id' => user.id, 'source' => 4, 'source_blob_id' => import.file.blob_id,
      'event_id' => event, 'action' => 'extract', 'started_at' => started }
  end

  before do
    import.file.attach(io: File.open(Rails.root.join('spec/fixtures/files/gpx/gpx_single_waypoint.gpx')),
                       filename: 'race.gpx', content_type: 'application/gpx+xml')
    import.update_columns(
      additional_data_extraction_status: 1, additional_data_extraction: {
        'phoenix_extraction_event' => event, 'phoenix_extraction_action' => 'extract',
        'started_at' => started, 'options' => { 'trust_source' => true }
      }
    )
  end

  after do
    import.reload.update_columns(user_id: user.id)
    User.unscoped.find(user.id).destroy!
    other_user.destroy!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def concurrent_change(attributes)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Import.find(import.id).update_columns(attributes)
      end
    end.value
  end

  def replace_run
    concurrent_change(additional_data_extraction: { 'phoenix_extraction_event' => SecureRandom.uuid,
      'phoenix_extraction_action' => 'remove', 'started_at' => Time.current.iso8601(6), 'new_run' => true })
    import.reload.additional_data_extraction
  end

  def pause_after_read
    allow_any_instance_of(EnhancedImport::Translator).to receive(:translate).and_wrap_original do |original, &block|
      original.call do |item|
        expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
        yield
        block.call(item)
      end
    end
  end

  it 'does not mark a replacement run running after initial admission' do
    snapshot = nil
    allow_any_instance_of(EnhancedImport::ExtractJob).to receive(:mark_running!).and_wrap_original do |original, *args|
      snapshot = replace_run
      original.call(*args)
    end
    EnhancedImport::ExtractJob.new.perform(import.id, expected: expected)
    expect(Place.where(import_id: import.id)).to be_empty
    expect(import.reload.additional_data_extraction).to eq(snapshot)
    expect(import.additional_data_extraction_status).to eq('pending')
  end

  it 'coordinates extraction with the real native destruction session lock' do
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        key = connection.quote("phoenix-import:#{import.id}")
        connection.execute("SELECT pg_advisory_lock(hashtextextended(#{key},0))")
        ready << true
        release.pop
        connection.execute("SELECT pg_advisory_unlock(hashtextextended(#{key},0))")
      end
    end
    Timeout.timeout(5) { ready.pop }
    expect { EnhancedImport::ExtractJob.new.perform(import.id, expected: expected) }
      .to raise_error(Imports::ExtractionCommands::Busy)
    expect(Place.where(import_id: import.id)).to be_empty
    expect(import.reload.additional_data_extraction_status).to eq('pending')
  ensure
    release << true
    holder&.join(5)
  end

  it 'rechecks identity after waiting for the actual per-user lock' do
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      Tracks::PerUserLock.with_user_lock(user.id) do
        ready << true
        release.pop
      end
    end
    Timeout.timeout(5) { ready.pop }
    waiting = Queue.new
    allow(Tracks::PerUserLock).to receive(:acquire!).and_wrap_original do |original, *args|
      waiting << true
      original.call(*args)
    end
    actor = expected
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        EnhancedImport::ExtractJob.new.perform(import.id, expected: actor)
      end
    end
    Timeout.timeout(5) { waiting.pop }
    snapshot = replace_run
    release << true
    expect(worker.join(10)).not_to be_nil
    worker.value
    expect(Place.where(import_id: import.id)).to be_empty
    expect(import.reload.additional_data_extraction).to eq(snapshot)
  ensure
    release << true
    holder&.join(5)
    worker&.join(5)
  end

  {
    source: -> { { source: Import.sources.fetch('google_phone_takeout') } },
    blob: -> { {} },
    event: lambda {
      { additional_data_extraction: import.reload.additional_data_extraction.merge(
        'phoenix_extraction_event' => SecureRandom.uuid
      ) }
    },
    action: lambda {
      { additional_data_extraction: import.reload.additional_data_extraction.merge(
        'phoenix_extraction_action' => 'remove'
      ) }
    },
    timestamp: lambda {
      { additional_data_extraction: import.reload.additional_data_extraction.merge(
        'started_at' => Time.current.iso8601(6)
      ) }
    },
    deleting: -> { { status: Import.statuses.fetch('deleting') } },
    actor: -> { { user_id: other_user.id } }
  }.each do |dimension, mutation|
    it "refuses a #{dimension} change after real GPX IO and before writing the first place" do
      actor = expected
      snapshot = nil
      pause_after_read do
        if dimension == :blob
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ActiveStorage::Attachment.find(import.file_attachment.id).update_columns(name: 'replaced')
            end
          end.value
        else
          concurrent_change(instance_exec(&mutation))
        end
        snapshot = import.reload.additional_data_extraction.deep_dup
      end
      EnhancedImport::ExtractJob.new.perform(import.id, expected: actor)
      expect(Place.where(import_id: import.id)).to be_empty
      expect(import.reload.additional_data_extraction).to eq(snapshot)
    end
  end

  it 'refuses a soft-deleted user after GPX IO' do
    actor = expected
    snapshot = nil
    pause_after_read do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          User.find(user.id).update_columns(deleted_at: Time.current)
        end
      end.value
      snapshot = import.reload.additional_data_extraction.deep_dup
    end
    EnhancedImport::ExtractJob.new.perform(import.id, expected: actor)
    expect(Place.where(import_id: import.id)).to be_empty
    expect(import.reload.additional_data_extraction).to eq(snapshot)
  end

  it 'does not mark a newer run retrying after an actual PostgreSQL writer error' do
    actor = expected
    snapshot = nil
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE FUNCTION reject_racing_place_insert() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'real extraction write failure'; END $$
    SQL
    connection.execute(<<~SQL)
      CREATE TRIGGER reject_racing_place_insert BEFORE INSERT ON places
      FOR EACH ROW EXECUTE FUNCTION reject_racing_place_insert()
    SQL
    allow_any_instance_of(EnhancedImport::ExtractJob).to receive(:mark_retrying!).and_wrap_original do |original, *args|
      snapshot = replace_run
      original.call(*args)
    end
    begin
      EnhancedImport::ExtractJob.new.perform(import.id, expected: actor)
      expect(Place.where(import_id: import.id)).to be_empty
      expect(import.reload.additional_data_extraction).to eq(snapshot)
      expect(import.additional_data_extraction_status).to eq('running')
    ensure
      connection.execute('DROP TRIGGER reject_racing_place_insert ON places')
      connection.execute('DROP FUNCTION reject_racing_place_insert()')
    end
  end

  it 'holds the import identity lock through the actual place write' do
    attempted = false
    allow_any_instance_of(EnhancedImport::Writers::PlaceWriter).to receive(:upsert)
      .and_wrap_original do |original, item|
      result = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute("SET LOCAL lock_timeout = '100ms'")
            Import.find(import.id).update_columns(status: Import.statuses.fetch('deleting'))
          end
          :changed
        rescue ActiveRecord::LockWaitTimeout
          :locked
        end
      end.value
      expect(result).to eq(:locked)
      attempted = true
      original.call(item)
    end
    EnhancedImport::ExtractJob.new.perform(import.id, expected: expected)
    expect(attempted).to be(true)
    expect(Place.where(import_id: import.id).count).to eq(1)
    expect(import.reload.additional_data_extraction_status).to eq('completed')
  end

  it 'does not complete a newer run after a real place was already committed' do
    actor = expected
    snapshot = nil
    allow_any_instance_of(EnhancedImport::ExtractJob).to receive(:mark_completed!)
      .and_wrap_original do |original, *args|
      snapshot = replace_run
      original.call(*args)
    end
    EnhancedImport::ExtractJob.new.perform(import.id, expected: actor)
    expect(Place.where(import_id: import.id).count).to eq(1)
    expect(import.reload.additional_data_extraction).to eq(snapshot)
    expect(import.additional_data_extraction_status).to eq('running')
  end

  it 'fences an exhausted error callback after its admission check' do
    actor = expected
    job = EnhancedImport::ExtractJob.new(import.id, expected: actor)
    snapshot = nil
    allow(job).to receive(:mark_failed!).and_wrap_original do |original, *args|
      snapshot = replace_run
      original.call(*args)
    end
    job.fail_after_retries(StandardError.new('old error'))
    expect(import.reload.additional_data_extraction).to eq(snapshot)
    expect(import.additional_data_extraction_status).to eq('pending')
  end

  it 'stops the real remover after admission if the extraction run changed' do
    place = create(:place, user:, import_id: import.id)
    actor = expected.merge('action' => 'remove')
    import.update_columns(additional_data_extraction_status: 2,
                          additional_data_extraction: import.additional_data_extraction.merge(
                            'phoenix_extraction_action' => 'remove'
                          ))
    snapshot = nil
    allow_any_instance_of(EnhancedImport::Destroy).to receive(:call).and_wrap_original do |original|
      snapshot = replace_run
      original.call
    end
    EnhancedImport::DestroyJob.new.perform(import.id, expected: actor)
    expect(Place.exists?(place.id)).to be(true)
    expect(import.reload.additional_data_extraction).to eq(snapshot)
  end

  it 'does not clear a new run at the removal terminal checkpoint' do
    place = create(:place, user:, import_id: import.id)
    actor = expected.merge('action' => 'remove')
    import.update_columns(additional_data_extraction_status: 2,
                          additional_data_extraction: import.additional_data_extraction.merge(
                            'phoenix_extraction_action' => 'remove'
                          ))
    snapshot = nil
    allow_any_instance_of(EnhancedImport::Destroy).to receive(:effect).and_wrap_original do |original, &block|
      snapshot = replace_run unless Place.exists?(place.id) || snapshot
      original.call(&block)
    end
    EnhancedImport::DestroyJob.new.perform(import.id, expected: actor)
    expect(Place.exists?(place.id)).to be(false)
    expect(import.reload.additional_data_extraction).to eq(snapshot)
    expect(import.additional_data_extraction_status).to eq('running')
  end

  it 'preserves a committed removal batch and stops later batches after token replacement' do
    actor = expected.merge('action' => 'remove')
    import.update_columns(additional_data_extraction_status: 2,
                          additional_data_extraction: import.additional_data_extraction.merge(
                            'phoenix_extraction_action' => 'remove'
                          ))
    now = Time.current
    Place.insert_all!(501.times.map do |index|
      { name: "Race batch #{index}", user_id: user.id, import_id: import.id,
        latitude: 54, longitude: 13, created_at: now, updated_at: now }
    end)
    snapshot = nil
    allow_any_instance_of(EnhancedImport::Destroy).to receive(:effect).and_wrap_original do |original, &block|
      result = original.call(&block)
      snapshot = replace_run if Place.where(import_id: import.id).count == 1 && !snapshot
      result
    end
    EnhancedImport::DestroyJob.new.perform(import.id, expected: actor)
    expect(Place.where(import_id: import.id).count).to eq(1)
    expect(import.reload.additional_data_extraction).to eq(snapshot)
  end

  it 'does not publish a real removal error onto a newer extraction token' do
    place = create(:place, user:, import_id: import.id)
    actor = expected.merge('action' => 'remove')
    import.update_columns(additional_data_extraction_status: 2,
                          additional_data_extraction: import.additional_data_extraction.merge(
                            'phoenix_extraction_action' => 'remove'
                          ))
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      CREATE FUNCTION reject_racing_place_delete() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'real remover failure'; END $$
    SQL
    connection.execute(<<~SQL)
      CREATE TRIGGER reject_racing_place_delete BEFORE DELETE ON places
      FOR EACH ROW EXECUTE FUNCTION reject_racing_place_delete()
    SQL
    snapshot = nil
    allow_any_instance_of(EnhancedImport::Destroy).to receive(:call).and_wrap_original do |original|
      original.call
    rescue ActiveRecord::StatementInvalid
      snapshot = replace_run
      raise
    end
    begin
      expect { EnhancedImport::DestroyJob.new.perform(import.id, expected: actor) }
        .to raise_error(ActiveRecord::StatementInvalid, /real remover failure/)
      expect(Place.exists?(place.id)).to be(true)
      expect(import.reload.additional_data_extraction).to eq(snapshot)
      expect(import.additional_data_extraction_status).to eq('running')
    ensure
      connection.execute('DROP TRIGGER reject_racing_place_delete ON places')
      connection.execute('DROP FUNCTION reject_racing_place_delete()')
    end
  end
end
