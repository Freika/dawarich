# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Retrying a prepared import upload', type: :model do
  self.use_transactional_tests = false

  it 'retries a failed destination upload without treating missing bytes as a ready file' do
    import = create(:import, name: 'holiday.gpx')
    user = import.user
    content = '<gpx><trk><name>Holiday</name></trk></gpx>'
    archive = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('original.gpx')
      zip.write(content)
    end
    import.file.attach(
      io: StringIO.new(archive.string), filename: 'original.gpx.zip', content_type: 'application/zip',
      metadata: { 'dawarich_client_wrapped' => true, 'dawarich_original_filename' => 'original.gpx' }
    )
    source_id = import.file.blob_id
    service = import.file.blob.service
    allow(service).to receive(:upload).and_raise(IOError, 'temporary write failure')

    expect { Imports::PrepareDownloadJob.perform_now(import.id, source_id) }.to raise_error(IOError)
    expect(Imports::Download.new(import.reload)).not_to be_ready

    allow(service).to receive(:upload).and_call_original
    Imports::PrepareDownloadJob.perform_now(import.id, source_id)

    expect(import.reload.prepared_download.download).to eq(content)
  ensure
    import&.destroy!
    user&.destroy!
  end
end
