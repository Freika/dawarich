# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe 'F2 original Rails prepared download deletion', type: :request do
  %i[prepared_only distinct].each do |layout|
    it "keeps issued prepared capabilities until delayed purge for #{layout} attachments" do
      paths = []
      import = build(:import, source: :gpx, status: :completed)
      import.skip_background_processing = true
      import.save!
      if layout == :distinct
        import.file.attach(io: StringIO.new('<gpx/>'), filename: 'source.gpx', content_type: 'application/gpx+xml')
        paths << import.file.blob.service.send(:path_for, import.file.blob.key)
      end
      import.prepared_download.attach(io: StringIO.new('<gpx/>'), filename: 'prepared.gpx',
                                      content_type: 'application/gpx+xml')
      blob = import.prepared_download.blob
      paths << blob.service.send(:path_for, blob.key)
      host! 'www.example.com'
      redirect = rails_blob_path(blob, only_path: true)
      disk = ActiveStorage::Current.set(url_options: { host: 'http://www.example.com' }) { blob.url }
      import.destroy!
      expect(Import.exists?(import.id)).to be(false)
      expect(ActiveStorage::Attachment.where(record_type: 'Import', record_id: import.id)).to be_empty
      get redirect
      expect(response).to have_http_status(:found)
      get disk
      expect(response).to have_http_status(:ok)
    ensure
      paths&.each { |path| File.delete(path) if File.file?(path) }
    end
  end
end
