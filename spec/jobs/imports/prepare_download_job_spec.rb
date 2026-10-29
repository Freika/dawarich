# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::PrepareDownloadJob do
  let(:import) { create(:import, name: 'renamed.gpx') }
  let(:content) { '<gpx><trk><name>Synthetic track</name></trk></gpx>' }

  before do
    archive = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('original.gpx')
      zip.write(content)
    end
    import.file.attach(
      io: StringIO.new(archive.string), filename: 'original.gpx.zip', content_type: 'application/zip',
      metadata: { 'dawarich_client_wrapped' => true, 'dawarich_original_filename' => 'original.gpx' }
    )
  end

  it 'prepares an inner file once and retains the original archive' do
    source = import.file.blob
    original = source.download
    described_class.perform_now(import.id, source.id)
    prepared_id = import.reload.prepared_download.blob_id

    expect(import.prepared_download.download).to eq(content)
    expect(import.prepared_download.blob.metadata['dawarich_download_source_blob_id']).to eq(source.id)
    described_class.perform_now(import.id, source.id)

    expect(import.reload.prepared_download.blob_id).to eq(prepared_id)
    expect(import.file.download).to eq(original)
  end

  it 'ignores a job for a replaced source file' do
    source_id = import.file.blob_id
    import.file.attach(io: StringIO.new('<gpx/>'), filename: 'replacement.gpx')

    described_class.perform_now(import.id, source_id)

    expect(import.reload.prepared_download).not_to be_attached
  end

  it 'ignores a deleted import' do
    id = import.id
    source_id = import.file.blob_id
    import.destroy!

    expect { described_class.perform_now(id, source_id) }.not_to raise_error
  end

  it 'can retry a failed storage read without keeping a partial attachment' do
    source_id = import.file.blob_id
    downloader = instance_double(Imports::SecureFileDownloader)
    allow(Imports::SecureFileDownloader).to receive(:new).and_return(downloader)
    allow(downloader).to receive(:download_to_temp_file).and_raise(IOError)
    expect { described_class.perform_now(import.id, source_id) }.to raise_error(IOError)
    expect(import.reload.prepared_download).not_to be_attached

    allow(Imports::SecureFileDownloader).to receive(:new).and_call_original
    described_class.perform_now(import.id, source_id)
    expect(import.reload.prepared_download.download).to eq(content)
  end
end
