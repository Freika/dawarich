# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports download command handoff' do
  let!(:import) { create(:import, source: :gpx, skip_background_processing: true) }
  let(:payload) { { 'import_id' => import.id, 'user_id' => import.user_id, 'source_blob_id' => import.file.blob_id } }

  before do
    phoenix_tables!
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'original.gpx')
  end

  it 'forwards a previously queued legacy job after Oban claims the lane' do
    job_owner!('command:imports.prepare_download', :oban)
    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id)
    expect(JobOutbox.pending.sole.payload).to eq(payload)
    expect(JobOutbox.pending.sole.command_type).to eq('imports.prepare_download')
    expect(import.reload.prepared_download).not_to be_attached
  end

  it 'honours an explicit admission fallback after ownership is restored' do
    job_owner!('command:imports.prepare_download', :oban)
    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id, native_fallback: true)
    expect(JobOutbox.count).to eq(0)
  end

  it 'dispatches native handback using the actual job and fallback flag' do
    expect { RailsCommands::Registry.handler('imports.prepare_download').call(payload.merge('native_fallback' => true)) }
      .to have_enqueued_job(Imports::PrepareDownloadJob).with(import.id, import.file.blob_id, native_fallback: true,
expected_user_id: import.user_id)
  end

  it 'rejects foreign user and stale source from reverse dispatch' do
    expect { RailsCommands::Registry.handler('imports.prepare_download').call(payload.merge('user_id' => import.user_id + 999)) }
      .not_to have_enqueued_job(Imports::PrepareDownloadJob)
    expect { RailsCommands::Registry.handler('imports.prepare_download').call(payload.merge('source_blob_id' => import.file.blob_id + 999)) }
      .not_to have_enqueued_job(Imports::PrepareDownloadJob)
  end
  it 'retains the queued actor instead of preparing another owner after reassignment' do
    original_user = import.user_id
    import.update!(user: create(:user))
    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id,
                                            native_fallback: true, expected_user_id: original_user)
    expect(import.reload.prepared_download).not_to be_attached
    expect(JobOutbox.count).to eq(0)
  end

  describe 'with a wrapped GPX download' do
    before do
      archive = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry('original.gpx')
        zip.write('<gpx/>')
      end
      import.file.attach(
        io: StringIO.new(archive.string), filename: 'original.gpx.zip', content_type: 'application/zip',
        metadata: { 'dawarich_client_wrapped' => true, 'dawarich_original_filename' => 'original.gpx' }
      )
    end

    it 'prepares it for an active user' do
      Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id)
      expect(import.reload.prepared_download.download).to eq('<gpx/>')
    end

    it 'does nothing for a soft-deleted user' do
      import.user.update_column(:deleted_at, Time.current)
      expect { Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id) }.not_to raise_error
      expect(import.reload.prepared_download).not_to be_attached
      expect(JobOutbox.count).to eq(0)
    end

    it 'enqueues nothing from the reverse command for a soft-deleted user' do
      import.user.update_column(:deleted_at, Time.current)
      handler = RailsCommands::Registry.handler('imports.prepare_download')
      expect { handler.call(payload.merge('native_fallback' => true)) }
        .not_to have_enqueued_job(Imports::PrepareDownloadJob)
    end
  end

  it 'prepares a non-GPX download under the same import lease, skipping it while another preparation holds it' do
    other = create(:import, source: :geojson, skip_background_processing: true)
    archive = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('original.geojson')
      zip.write('{"type":"FeatureCollection","features":[]}')
    end
    other.file.attach(
      io: StringIO.new(archive.string), filename: 'original.geojson.zip', content_type: 'application/zip',
      metadata: { 'dawarich_client_wrapped' => true, 'dawarich_original_filename' => 'original.geojson' }
    )
    hold_import_lock("import-download:#{other.id}") do
      Imports::PrepareDownloadJob.perform_now(other.id, other.file.blob_id)
      expect(other.reload.prepared_download).not_to be_attached
    end
    Imports::PrepareDownloadJob.perform_now(other.id, other.file.blob_id)
    expect(other.reload.prepared_download.download).to eq('{"type":"FeatureCollection","features":[]}')
  end

  it 'retries a busy GPX download preparation ten times, then stops with a warning and leaves the import' do
    allow(Rails.logger).to receive(:warn)
    hold_import_lock("import-download:#{import.id}") do
      perform_enqueued_jobs { Imports::PrepareDownloadJob.perform_later(import.id, import.file.blob_id) }
    end
    expect(performed_jobs.count { |entry| entry[:job] == Imports::PrepareDownloadJob }).to eq(10)
    expect(import.reload).to have_attributes(status: 'created', error_message: nil)
    expect(import.prepared_download).not_to be_attached
    expect(Rails.logger).to have_received(:warn)
      .with("[imports] import #{import.id}: download preparation stopped, another preparation kept it busy")
  end
end
