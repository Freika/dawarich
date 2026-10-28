# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::DeleteSourceFile, :non_transactional, threads: 3 do
  let(:import) { create(:import, status: :completed, source: :owntracks, skip_background_processing: true) }

  before do
    import.file.attach(io: StringIO.new('synthetic source'), filename: 'synthetic.json')
  end

  after { import.user.destroy! }

  def remove_source(record = import)
    described_class.new(record).call
  end

  it 'keeps the import, point IDs and extracted entities while purging both files in the background' do
    place = create(:place, user: import.user, import_id: import.id)
    visit = create(:visit, user: import.user, place: place, import_id: import.id)
    track = create(:track, user: import.user, import_id: import.id)
    points = create_list(:point, 2, user: import.user, import: import, track: track)
    import.prepared_download.attach(io: StringIO.new('synthetic download'), filename: 'download.json')
    blobs = [import.file.blob, import.prepared_download.blob]
    original_attributes = import.reload.attributes.except('updated_at')

    expect { expect(remove_source).to eq(:deleted) }
      .to have_enqueued_job(ActiveStorage::PurgeJob).exactly(2).times

    expect(import.reload.attributes.except('updated_at')).to eq(original_attributes)
    expect(import.points.order(:id).pluck(:id)).to eq(points.map(&:id).sort)
    expect(import.extracted_places.pluck(:id)).to eq([place.id])
    expect(import.extracted_visits.pluck(:id)).to eq([visit.id])
    expect(import.extracted_tracks.pluck(:id)).to eq([track.id])
    expect(import.file).not_to be_attached
    expect(import.prepared_download).not_to be_attached
    expect(blobs).to all(satisfy { |blob| blob.service.exist?(blob.key) })

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    expect(blobs).to all(satisfy { |blob| !blob.service.exist?(blob.key) })
    expect(import.points.order(:id).pluck(:id)).to eq(points.map(&:id).sort)

    Dir.mktmpdir('synthetic-import-export') do |directory|
      rows = Users::ExportData::Imports.new(import.user, Pathname.new(directory)).call
      expect(rows.first).to include('name' => import.name, 'file_name' => nil, 'original_filename' => nil)
      expect(Dir.children(directory)).to be_empty
    end
    expect(TransportationModes::ActivityBackfiller.new(import).call).to be false
  end

  it 'purges a shared source/prepared blob only once, after detaching both references' do
    blob = import.file.blob
    import.prepared_download.attach(blob)

    expect { remove_source }.to have_enqueued_job(ActiveStorage::PurgeJob).with(blob).exactly(:once)
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)

    expect(ActiveStorage::Blob.exists?(blob.id)).to be false
    expect(blob.service.exist?(blob.key)).to be false
  end

  it 'keeps a blob attached to another import' do
    blob = import.file.blob
    other = create(:import, user: import.user, skip_background_processing: true)
    other.file.attach(blob)

    remove_source
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)

    expect(other.reload.file.download).to eq('synthetic source')
    expect(ActiveStorage::Blob.exists?(blob.id)).to be true
  end

  it 'is idempotent, including a request holding a stale import instance' do
    stale = Import.find(import.id)
    stale.file.blob
    expect(remove_source).to eq(:deleted)

    expect { expect(remove_source(stale)).to eq(:already_deleted) }
      .not_to have_enqueued_job(ActiveStorage::PurgeJob)
  end

  it 'keeps the attachments and does not purge storage if the enclosing transaction rolls back' do
    expect do
      Import.transaction do
        expect(remove_source).to eq(:deleted)
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(ActiveStorage::PurgeJob)

    expect(import.reload.file.download).to eq('synthetic source')
  end

  %i[created processing deleting].each do |status|
    it "refuses an import that is #{status}" do
      import.update_columns(status: Import.statuses.fetch(status))
      expect(remove_source).to eq(:unavailable)
      expect(import.reload.file).to be_attached
    end
  end

  %i[pending running].each do |status|
    it "refuses #{status} extraction, even when marked stale" do
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses.fetch(status),
        additional_data_extraction: { 'started_at' => 8.hours.ago.iso8601 }
      )
      expect(remove_source).to eq(:unavailable)
      expect(import.reload.file).to be_attached
    end
  end

  it 'allows failed imports and failed extractions' do
    import.update_columns(status: Import.statuses[:failed],
                          additional_data_extraction_status: Import.additional_data_extraction_statuses[:failed])
    expect(remove_source).to eq(:deleted)
  end

  %i[user_data_archive immich_api photoprism_api].each do |source|
    it "refuses #{source} even when its status says completed" do
      import.update_columns(source: Import.sources.fetch(source))
      expect(remove_source).to eq(:unavailable)
    end
  end

  it 'refuses queued download preparation' do
    import.update!(download_preparation_pending: true)
    expect(remove_source).to eq(:unavailable)
    expect(import.reload.file).to be_attached
  end

  it 'refuses removal while a reader owns the source lock, then allows it after the reader finishes' do
    started = Queue.new
    release = Queue.new
    reader = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Import.find(import.id).with_source_file_lock do
          started << true
          release.pop
        end
      end
    end
    Timeout.timeout(5) { started.pop }

    expect(remove_source).to eq(:unavailable)
    expect(import.reload.file).to be_attached
    release << true
    reader.value
    expect(remove_source).to eq(:deleted)
  ensure
    release << true if reader&.alive?
    reader&.join(5)
  end

  it 'rechecks attachment availability when extraction is claimed from a stale instance' do
    import.update_columns(source: Import.sources[:google_phone_takeout])
    stale = Import.find(import.id)
    stale.file.blob
    remove_source

    expect(stale.claim_additional_data_extraction!({})).to be false
  end

  it 'refuses deletion when extraction wins the claim before deletion' do
    expect(import.claim_additional_data_extraction!({})).to be true
    expect(remove_source).to eq(:unavailable)
  end

  it 'skips a stale processing job after deletion without changing the import status or points' do
    source_blob_id = import.file.blob_id
    stale = Import.find(import.id)
    stale.file.blob
    service = Imports::Create.new(stale.user, stale)
    remove_source
    expect(Imports::SecureFileDownloader).not_to receive(:new)
    service.call
    expect { Import::ProcessJob.perform_now(import.id) }.not_to change(Point, :count)
    expect { Imports::PrepareDownloadJob.perform_now(import.id, source_blob_id) }.not_to raise_error
    expect(import.reload.status).to eq('completed')
    expect(import.prepared_download).not_to be_attached
  end

  it 'protects an account backup while it reads the source' do
    started = Queue.new
    release = Queue.new
    downloader = instance_double(Imports::SecureFileDownloader)
    allow(Imports::SecureFileDownloader).to receive(:new).and_return(downloader)
    allow(downloader).to receive(:download_with_verification) do
      started << true
      release.pop
      'synthetic source'
    end
    Dir.mktmpdir('synthetic-import-export') do |directory|
      reader = Thread.new { Users::ExportData::Imports.new(import.user, Pathname.new(directory)).call }
      Timeout.timeout(5) { started.pop }
      expect(remove_source).to eq(:unavailable)

      release << true
      expect(reader.value.first).to include('original_filename' => 'synthetic.json')
      expect(remove_source).to eq(:deleted)
    ensure
      release << true if reader&.alive?
      reader&.join(5)
    end
  end

  it 'refuses removal after processing starts reading but before it updates the status' do
    started = Queue.new
    release = Queue.new
    downloader = instance_double(Imports::SecureFileDownloader)
    allow(Imports::SecureFileDownloader).to receive(:new).and_return(downloader)
    allow(downloader).to receive(:download_to_temp_file) do
      started << true
      release.pop
      raise IOError, 'synthetic read failure'
    end
    reader = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        record = Import.find(import.id)
        Imports::Create.new(record.user, record).call
      end
    end
    Timeout.timeout(5) { started.pop }

    expect(import.reload.status).to eq('completed')
    expect(remove_source).to eq(:unavailable)
    expect(import.reload.file).to be_attached

    release << true
    reader.value
    expect(remove_source).to eq(:deleted)
  ensure
    release << true if reader&.alive?
    reader&.join(5)
  end

  it 'protects device-tag backfill while it streams the source' do
    import.update_columns(source: Import.sources[:google_records])
    create(:point, user: import.user, import: import, tracker_id: nil)
    started = Queue.new
    release = Queue.new
    backfiller = Points::DeviceTagBackfiller.new(import)
    allow(backfiller).to receive(:read_source) do
      started << true
      release.pop
      [{}, {}]
    end
    reader = Thread.new { backfiller.call }
    Timeout.timeout(5) { started.pop }

    expect(remove_source).to eq(:unavailable)
    expect(import.reload.file).to be_attached
    release << true
    expect(reader.value).to eq(0)
    expect(remove_source).to eq(:deleted)
    expect(Points::DeviceTagBackfiller.new(import).call).to eq(0)
  ensure
    release << true if reader&.alive?
    reader&.join(5)
  end
end
