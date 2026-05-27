# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GeoJSON track without timestamps raises a clear error' do
  subject(:run_import) { Geojson::Importer.new(import, user.id).call }

  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/geojson_timeless_track.json') }
  let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
  let(:import) { create(:import, user:, name: 'track.json', source: 'geojson') }

  before do
    import.file.attach(io: File.open(file_path), filename: 'track.json', content_type: 'application/json')
  end

  it 'raises Imports::NoImportableDataError with a user-facing message' do
    expect { run_import }.to raise_error(Imports::NoImportableDataError, /No importable locations/)
  end

  it 'creates no Points and no Places' do
    expect do
      run_import
    rescue Imports::NoImportableDataError
      nil
    end.not_to(change { Point.count + Place.count })
  end
end
