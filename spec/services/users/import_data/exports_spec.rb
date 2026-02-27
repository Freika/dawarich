# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Exports, type: :service do
  let(:user) { create(:user) }
  let(:files_directory) { Rails.root.join('tmp', "test_exports_import_#{Time.current.to_i}") }

  before do
    FileUtils.mkdir_p(files_directory)
  end

  after do
    FileUtils.rm_rf(files_directory)
  end

  describe '#call' do
    context 'when exports_data is not an array' do
      it 'returns [0, 0] for nil' do
        service = described_class.new(user, nil, files_directory)
        expect(service.call).to eq([0, 0])
      end

      it 'returns [0, 0] for a hash' do
        service = described_class.new(user, { 'name' => 'test' }, files_directory)
        expect(service.call).to eq([0, 0])
      end
    end

    context 'when exports_data is empty' do
      it 'returns [0, 0]' do
        service = described_class.new(user, [], files_directory)
        expect(service.call).to eq([0, 0])
      end
    end

    context 'with valid exports data without files' do
      let(:exports_data) do
        [
          {
            'name' => 'Q1 2024 Export',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'start_at' => '2024-01-01T00:00:00Z',
            'end_at' => '2024-03-31T23:59:59Z',
            'created_at' => '2024-04-01T10:00:00Z',
            'file_name' => nil,
            'original_filename' => nil
          },
          {
            'name' => 'Q2 2024 Export',
            'file_format' => 'gpx',
            'file_type' => 'points',
            'status' => 'completed',
            'start_at' => '2024-04-01T00:00:00Z',
            'end_at' => '2024-06-30T23:59:59Z',
            'created_at' => '2024-07-01T10:00:00Z',
            'file_name' => nil,
            'original_filename' => nil
          }
        ]
      end

      it 'creates the exports' do
        service = described_class.new(user, exports_data, files_directory)

        expect { service.call }.to change { user.exports.count }.by(2)
      end

      it 'returns [exports_created, files_restored]' do
        service = described_class.new(user, exports_data, files_directory)

        expect(service.call).to eq([2, 0])
      end

      it 'sets the correct attributes' do
        service = described_class.new(user, exports_data, files_directory)
        service.call

        export = user.exports.find_by(name: 'Q1 2024 Export')
        expect(export).to be_present
        expect(export.file_format).to eq('json')
        expect(export.file_type).to eq('points')
        expect(export.status).to eq('completed')
      end
    end

    context 'with exports that have attached files' do
      let(:exports_data) do
        [
          {
            'name' => 'Export with File',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'created_at' => '2024-01-01T10:00:00Z',
            'file_name' => 'export_1_points.json',
            'original_filename' => 'points.json',
            'file_size' => 1024,
            'content_type' => 'application/json'
          }
        ]
      end

      before do
        # Create the file in the files directory
        File.write(files_directory.join('export_1_points.json'), '{"type":"FeatureCollection","features":[]}')
      end

      it 'creates the export and attaches the file' do
        service = described_class.new(user, exports_data, files_directory)
        exports_created, files_restored = service.call

        expect(exports_created).to eq(1)
        expect(files_restored).to eq(1)

        export = user.exports.find_by(name: 'Export with File')
        expect(export.file).to be_attached
        expect(export.file.filename.to_s).to eq('points.json')
      end
    end

    context 'when file is missing from files directory' do
      let(:exports_data) do
        [
          {
            'name' => 'Export with Missing File',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'created_at' => '2024-01-01T10:00:00Z',
            'file_name' => 'missing_file.json',
            'original_filename' => 'points.json'
          }
        ]
      end

      it 'creates the export but does not restore the file' do
        service = described_class.new(user, exports_data, files_directory)
        exports_created, files_restored = service.call

        expect(exports_created).to eq(1)
        expect(files_restored).to eq(0)

        export = user.exports.find_by(name: 'Export with Missing File')
        expect(export).to be_present
        expect(export.file).not_to be_attached
      end
    end

    context 'with duplicate exports' do
      let(:exports_data) do
        [
          {
            'name' => 'Duplicate Export',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'created_at' => '2024-01-01T10:00:00Z'
          }
        ]
      end

      let!(:existing_export) do
        create(:export,
               user: user,
               name: 'Duplicate Export',
               created_at: Time.zone.parse('2024-01-01T10:00:00Z'))
      end

      it 'skips the duplicate export' do
        service = described_class.new(user, exports_data, files_directory)

        expect { service.call }.not_to(change { user.exports.count })
      end

      it 'returns [0, 0] for skipped exports' do
        service = described_class.new(user, exports_data, files_directory)

        expect(service.call).to eq([0, 0])
      end
    end

    context 'with invalid export data' do
      let(:exports_data) do
        [
          { 'not_an_export' => 'invalid' },
          'string_instead_of_hash',
          nil,
          {
            'name' => 'Valid Export',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'created_at' => '2024-01-01T10:00:00Z'
          }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        service = described_class.new(user, exports_data, files_directory)
        exports_created, _files_restored = service.call

        expect(exports_created).to eq(1)
        expect(user.exports.find_by(name: 'Valid Export')).to be_present
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:other_user_export) do
        create(:export,
               user: other_user,
               name: 'Other User Export',
               created_at: Time.zone.parse('2024-01-01T10:00:00Z'))
      end

      let(:exports_data) do
        [
          {
            'name' => 'Other User Export',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'created_at' => '2024-01-01T10:00:00Z'
          }
        ]
      end

      it 'creates the export for the target user (not a duplicate across users)' do
        service = described_class.new(user, exports_data, files_directory)

        expect { service.call }.to change { user.exports.count }.by(1)
      end
    end

    context 'with file_error in export data' do
      let(:exports_data) do
        [
          {
            'name' => 'Export with Error',
            'file_format' => 'json',
            'file_type' => 'points',
            'status' => 'completed',
            'created_at' => '2024-01-01T10:00:00Z',
            'file_name' => 'error_file.json',
            'file_error' => 'Failed to download: Connection timeout'
          }
        ]
      end

      it 'creates the export but does not try to restore the file' do
        service = described_class.new(user, exports_data, files_directory)
        exports_created, files_restored = service.call

        expect(exports_created).to eq(1)
        expect(files_restored).to eq(0)
      end
    end
  end
end
