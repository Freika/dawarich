# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Preparing a GPX download next to the user’s writes', :non_transactional, threads: 3 do
  let(:newest_blob_id) { ActiveStorage::Blob.maximum(:id).to_i }
  let(:import) { create(:import, name: 'holiday.gpx', source: :gpx, skip_background_processing: true) }
  let(:service) { import.file.blob.service }
  let(:content) { '<gpx><trk><name>Holiday</name></trk></gpx>' }

  before do
    newest_blob_id
    archive = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('original.gpx')
      zip.write(content)
    end
    import.file.attach(
      io: StringIO.new(archive.string), filename: 'original.gpx.zip', content_type: 'application/zip',
      metadata: { 'dawarich_client_wrapped' => true, 'dawarich_original_filename' => 'original.gpx' }
    )
  end

  after do
    Import.where(id: import.id).find_each(&:destroy!)
    ActiveStorage::Blob.where('id > ?', newest_blob_id).find_each(&:purge)
  end

  def pause_upload
    reached = Concurrent::CountDownLatch.new(1)
    release = Concurrent::CountDownLatch.new(1)
    allow(service).to receive(:upload).and_wrap_original do |original, *args, **kwargs, &block|
      reached.count_down
      release.wait(10)
      original.call(*args, **kwargs, &block)
    end
    [reached, release]
  end

  def pause_after_attachment_insert
    reached = Concurrent::CountDownLatch.new(1)
    release = Concurrent::CountDownLatch.new(1)
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      next unless payload[:sql].start_with?('INSERT INTO "active_storage_attachments"') && reached.count.positive?

      reached.count_down
      release.wait(10)
    end
    [reached, release, subscriber]
  end

  def prepare_in_thread
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id)
      end
    end
  end

  def insert_point_without_waiting(timestamp)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
      sql = <<~SQL.squish
        INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at)
        VALUES (?, ?, ST_SetSRID(ST_MakePoint(12.37, 51.34), 4326)::geography, now(), now())
      SQL
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, import.user_id, timestamp]))
    end
  end

  def lock_user_and_import_without_waiting
    ActiveRecord::Base.transaction do
      User.lock('FOR NO KEY UPDATE NOWAIT').find(import.user_id).touch
      Import.lock('FOR UPDATE NOWAIT').find(import.id)
    end
  end

  it 'leaves the user and the import unlocked during the upload and lets point inserts through the attach' do
    uploading, release_upload = pause_upload
    attaching, release_attach, subscriber = pause_after_attachment_insert
    thread = prepare_in_thread

    expect(uploading.wait(10)).to be(true)
    expect { insert_point_without_waiting(100) }.not_to raise_error
    expect { lock_user_and_import_without_waiting }.not_to raise_error
    release_upload.count_down

    expect(attaching.wait(10)).to be(true)
    expect { insert_point_without_waiting(200) }.not_to raise_error
    release_attach.count_down
    Timeout.timeout(15) { thread.join }

    expect(Point.where(user_id: import.user_id).count).to eq(2)
    expect(import.reload.prepared_download.download).to eq(content)
  ensure
    release_upload&.count_down
    release_attach&.count_down
    thread&.join
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it 'refuses the attach when the source changes during the upload and purges the uploaded blob' do
    uploading, release_upload = pause_upload
    thread = prepare_in_thread

    expect(uploading.wait(10)).to be(true)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '2s'")
      import.file.blob.update!(filename: 'replacement.gpx.zip')
    end
    release_upload.count_down
    Timeout.timeout(15) { thread.join }

    expect(import.reload.prepared_download).not_to be_attached
    uploaded = ActiveStorage::Blob.where('id > ?', newest_blob_id).where.not(id: import.file.blob_id).sole
    expect(ActiveStorage::PurgeJob).to have_been_enqueued.with(uploaded)
  ensure
    release_upload&.count_down
    thread&.join
  end
end
