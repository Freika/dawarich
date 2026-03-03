# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::RawDataArchives, type: :service do
  let(:user) { create(:user) }
  let(:files_directory) { Rails.root.join('tmp', "test_raw_archives_import_#{Time.current.to_i}") }

  before do
    FileUtils.mkdir_p(files_directory)
  end

  after do
    FileUtils.rm_rf(files_directory)
  end

  describe '#call' do
    context 'when archives_data is not an array' do
      it 'returns [0, 0] for nil' do
        service = described_class.new(user, nil, files_directory)
        expect(service.call).to eq([0, 0])
      end
    end

    context 'when archives_data is empty' do
      it 'returns [0, 0]' do
        service = described_class.new(user, [], files_directory)
        expect(service.call).to eq([0, 0])
      end
    end

    context 'with valid archive data without files' do
      let(:archives_data) do
        [
          {
            'year' => 2024,
            'month' => 6,
            'chunk_number' => 1,
            'point_count' => 100,
            'point_ids_checksum' => Digest::SHA256.hexdigest('1,2,3'),
            'archived_at' => '2024-07-01T00:00:00Z',
            'metadata' => { 'format_version' => 1, 'expected_count' => 100, 'actual_count' => 100 }
          }
        ]
      end

      it 'creates the archive record' do
        service = described_class.new(user, archives_data, files_directory)

        expect { service.call }.to change { user.raw_data_archives.count }.by(1)
      end

      it 'returns [archives_created, files_restored]' do
        service = described_class.new(user, archives_data, files_directory)

        expect(service.call).to eq([1, 0])
      end
    end

    context 'with archive data and attached file' do
      let(:archives_data) do
        [
          {
            'year' => 2024,
            'month' => 6,
            'chunk_number' => 1,
            'point_count' => 100,
            'point_ids_checksum' => Digest::SHA256.hexdigest('1,2,3'),
            'archived_at' => '2024-07-01T00:00:00Z',
            'metadata' => { 'format_version' => 1, 'expected_count' => 100, 'actual_count' => 100 },
            'file_name' => 'raw_data_archive_2024_06_1.gz',
            'original_filename' => 'archive.jsonl.gz',
            'content_type' => 'application/gzip'
          }
        ]
      end

      before do
        # Create a gzip test file
        File.open(files_directory.join('raw_data_archive_2024_06_1.gz'), 'wb') do |f|
          gz = Zlib::GzipWriter.new(f)
          gz.puts({ id: 1, raw_data: { lon: 13.4, lat: 52.5 } }.to_json)
          gz.close
        end
      end

      it 'creates the archive and attaches the file' do
        service = described_class.new(user, archives_data, files_directory)
        archives_created, files_restored = service.call

        expect(archives_created).to eq(1)
        expect(files_restored).to eq(1)

        archive = user.raw_data_archives.first
        expect(archive.file).to be_attached
      end
    end

    context 'with duplicate archives' do
      let(:archives_data) do
        [
          {
            'year' => 2024,
            'month' => 6,
            'chunk_number' => 1,
            'point_count' => 100,
            'point_ids_checksum' => Digest::SHA256.hexdigest('1,2,3'),
            'archived_at' => '2024-07-01T00:00:00Z',
            'metadata' => { 'format_version' => 1, 'expected_count' => 100, 'actual_count' => 100 }
          }
        ]
      end

      let!(:existing_archive) do
        create(:points_raw_data_archive, user: user, year: 2024, month: 6, chunk_number: 1)
      end

      it 'skips the duplicate archive' do
        service = described_class.new(user, archives_data, files_directory)

        expect { service.call }.not_to(change { user.raw_data_archives.count })
      end
    end
  end
end
