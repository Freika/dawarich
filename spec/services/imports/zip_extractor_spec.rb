# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe Imports::ZipExtractor do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, name: 'test_archive.zip') }

  describe '#call' do
    context 'with mixed format ZIP' do
      let(:zip_path) do
        path = Rails.root.join('tmp', "test_mixed_#{SecureRandom.hex(4)}.zip").to_s
        ::Zip::File.open(path, create: true) do |zipfile|
          gpx_content = File.read(Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx'))
          zipfile.get_output_stream('track.gpx') { |f| f.write(gpx_content) }

          csv_content = File.read(Rails.root.join('spec/fixtures/files/csv/gpslogger.csv'))
          zipfile.get_output_stream('data.csv') { |f| f.write(csv_content) }

          zipfile.get_output_stream('readme.txt') { |f| f.write('just a text file') }
        end
        path
      end

      after { File.delete(zip_path) if File.exist?(zip_path) }

      it 'creates imports for supported files only' do
        import # force-create before measuring count
        expect do
          described_class.new(import, user.id, zip_path).call
        end.to change { user.imports.count }.by(1) # 2 new - 1 destroyed ZIP = net +1
      end

      it 'names imports with archive reference' do
        described_class.new(import, user.id, zip_path).call
        names = user.imports.pluck(:name)
        expect(names).to include('track.gpx (from test_archive.zip)')
        expect(names).to include('data.csv (from test_archive.zip)')
      end

      it 'destroys the original ZIP import' do
        described_class.new(import, user.id, zip_path).call
        expect(Import.exists?(import.id)).to be false
      end

      it 'skips unsupported file types' do
        described_class.new(import, user.id, zip_path).call
        names = user.imports.pluck(:name)
        expect(names).not_to include(a_string_matching(/readme\.txt/))
      end
    end

    context 'with Google Takeout structure' do
      let(:zip_path) do
        path = Rails.root.join('tmp', "test_takeout_#{SecureRandom.hex(4)}.zip").to_s
        ::Zip::File.open(path, create: true) do |zipfile|
          json_content = '{"timelineObjects":[]}'
          zipfile.get_output_stream('Semantic Location History/2024/2024_JANUARY.json') { |f| f.write(json_content) }
          zipfile.get_output_stream('Semantic Location History/2024/2024_FEBRUARY.json') { |f| f.write(json_content) }
          zipfile.get_output_stream('Settings.json') { |f| f.write('{}') }
        end
        path
      end

      after { File.delete(zip_path) if File.exist?(zip_path) }

      it 'detects Google Takeout structure' do
        described_class.new(import, user.id, zip_path).call
        imports = user.imports.where.not(id: import.id)
        expect(imports.count).to eq(2)
      end

      it 'sets correct source for Semantic History files' do
        described_class.new(import, user.id, zip_path).call
        imports = user.imports.where(source: :google_semantic_history)
        expect(imports.count).to eq(2)
      end

      it 'skips non-location files like Settings.json' do
        described_class.new(import, user.id, zip_path).call
        names = user.imports.pluck(:name)
        expect(names).not_to include(a_string_matching(/Settings\.json/))
      end
    end

    context 'with path traversal attempt' do
      let(:zip_path) do
        path = Rails.root.join('tmp', "test_traversal_#{SecureRandom.hex(4)}.zip").to_s
        ::Zip::File.open(path, create: true) do |zipfile|
          zipfile.get_output_stream('safe.csv') { |f| f.write("lat,lon,time\n52.52,13.405,2024-01-01T00:00:00Z\n") }
        end
        path
      end

      after { File.delete(zip_path) if File.exist?(zip_path) }

      it 'extracts safe files' do
        described_class.new(import, user.id, zip_path).call
        expect(user.imports.where.not(id: import.id).count).to eq(1)
      end
    end

    context 'with nested ZIP' do
      let(:zip_path) do
        path = Rails.root.join('tmp', "test_nested_#{SecureRandom.hex(4)}.zip").to_s
        ::Zip::File.open(path, create: true) do |zipfile|
          zipfile.get_output_stream('data.csv') { |f| f.write("lat,lon,time\n52.52,13.405,2024-01-01T00:00:00Z\n") }
          zipfile.get_output_stream('nested.zip') { |f| f.write('PK fake nested zip') }
        end
        path
      end

      after { File.delete(zip_path) if File.exist?(zip_path) }

      it 'skips nested .zip files' do
        described_class.new(import, user.id, zip_path).call
        names = user.imports.pluck(:name)
        expect(names).not_to include(a_string_matching(/nested\.zip/))
      end
    end

    context 'when extraction fails' do
      let(:zip_path) { '/nonexistent/path/to/archive.zip' }

      it 'marks the import as failed with the error message' do
        expect do
          described_class.new(import, user.id, zip_path).call
        end.to raise_error(StandardError)

        import.reload
        expect(import.status).to eq('failed')
        expect(import.error_message).to be_present
      end
    end
  end
end
