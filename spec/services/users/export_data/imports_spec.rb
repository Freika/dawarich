# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Imports, type: :service do
  let(:user) { create(:user) }
  let(:files_directory) { Pathname.new(Dir.mktmpdir('test_exports')) }
  let(:service) { described_class.new(user, files_directory) }

  after do
    FileUtils.rm_rf(files_directory) if files_directory.exist?
  end

  describe '#call' do
    context 'when user has no imports' do
      it 'returns an empty array' do
        result = service.call
        expect(result).to eq([])
      end
    end

    context 'when user has imports without files' do
      let!(:import1) { create(:import, user: user, name: 'Import 1') }
      let!(:import2) { create(:import, user: user, name: 'Import 2') }

      it 'returns import data without file information' do
        result = service.call
        expect(result.size).to eq(2)

        first_import = result.find { |i| i['name'] == 'Import 1' }
        expect(first_import['file_name']).to be_nil
        expect(first_import['original_filename']).to be_nil
        expect(first_import).not_to have_key('user_id')
        expect(first_import).not_to have_key('raw_data')
        expect(first_import).not_to have_key('id')
      end

      it 'logs processing information' do
        expect(Rails.logger).to receive(:info).at_least(:once)
        service.call
      end
    end

    context 'when user has imports with attached files' do
      let(:file_content) { 'test file content' }
      let(:blob) { create_blob(filename: 'test_file.json', content_type: 'application/json') }
      let!(:import_with_file) do
        import = create(:import, user: user, name: 'Import with File')
        import.file.attach(blob)
        import
      end

      before do
        allow(Imports::SecureFileDownloader).to receive(:new).and_return(
          double(download_with_verification: file_content)
        )
      end

      it 'returns import data with file information' do
        result = service.call
        import_data = result.first

        expect(import_data['name']).to eq('Import with File')
        expect(import_data['file_name']).to eq("import_#{import_with_file.id}_test_file.json")
        expect(import_data['original_filename']).to eq('test_file.json')
        expect(import_data['file_size']).to be_present
        expect(import_data['content_type']).to eq('application/json')
      end

      it 'downloads and saves the file to the files directory' do
        result = service.call
        import_data = result.first

        file_path = files_directory.join(import_data['file_name'])
        expect(File.exist?(file_path)).to be true
        expect(File.read(file_path)).to eq(file_content)
      end

      it 'sanitizes the filename' do
        blob = create_blob(filename: 'test file with spaces & symbols!.json')
        import_with_file.file.attach(blob)

        result = service.call
        import_data = result.first

        expect(import_data['file_name']).to match(/import_\d+_test_file_with_spaces___symbols_.json/)
      end
    end

    context 'when file download fails' do
      let!(:import_with_file) do
        import = create(:import, user: user, name: 'Import with error file')
        import.file.attach(create_blob)
        import
      end

      before do
        allow(Imports::SecureFileDownloader).to receive(:new).and_raise(StandardError, 'Download failed')
      end

      it 'handles download errors gracefully' do
        result = service.call
        import_data = result.find { |i| i['name'] == 'Import with error file' }

        expect(import_data['file_error']).to eq('Failed to download: Download failed')
      end
    end

    context 'with single import (no parallel processing)' do
      let!(:import) { create(:import, user: user, name: 'Single import') }

      it 'processes without using parallel threads' do
        expect(Parallel).not_to receive(:map)
        service.call
      end
    end

    context 'with multiple imports (parallel processing)' do
      let!(:import1) { create(:import, user: user, name: 'Multiple Import 1') }
      let!(:import2) { create(:import, user: user, name: 'Multiple Import 2') }
      let!(:import3) { create(:import, user: user, name: 'Multiple Import 3') }

      let!(:imports) { [import1, import2, import3] }

      it 'uses parallel processing with limited threads' do
        expect(Parallel).to receive(:map).with(anything, in_threads: 2).and_call_original
        service.call
      end

      it 'returns all imports' do
        result = service.call
        expect(result.size).to eq(3)
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_import) { create(:import, user: user, name: 'User Import') }
      let!(:other_user_import) { create(:import, user: other_user, name: 'Other User Import') }

      it 'only returns imports for the specified user' do
        result = service.call
        expect(result.size).to eq(1)
        expect(result.first['name']).to eq('User Import')
      end
    end

    context 'performance considerations' do
      let!(:import1) { create(:import, user: user, name: 'Perf Import 1') }
      let!(:import2) { create(:import, user: user, name: 'Perf Import 2') }

      let!(:imports_with_files) { [import1, import2] }

      before do
        imports_with_files.each do |import|
          import.file.attach(create_blob)
        end
      end

      it 'includes file_attachment to avoid N+1 queries' do
        # This test verifies that we're using .includes(:file_attachment)
        expect(user.imports).to receive(:includes).with(:file_attachment).and_call_original
        service.call
      end
    end
  end

  describe 'private methods' do
    let(:import) { create(:import, user: user, name: 'Test Import') }

    describe '#process_import' do
      context 'with import without file' do
        it 'processes import correctly' do
          result = service.send(:process_import, import)

          expect(result).to include(
            'name' => 'Test Import',
            'file_name' => nil,
            'original_filename' => nil
          )
          expect(result).not_to have_key('user_id')
          expect(result).not_to have_key('raw_data')
          expect(result).not_to have_key('id')
        end
      end

      context 'with import with file' do
        let(:blob) { create_blob(filename: 'test.json', content_type: 'application/json') }

        before do
          import.file.attach(blob)
          allow(Imports::SecureFileDownloader).to receive(:new).and_return(
            double(download_with_verification: 'file content')
          )
        end

        it 'processes import with file data' do
          result = service.send(:process_import, import)

          expect(result['file_name']).to be_present
          expect(result['original_filename']).to eq('test.json')
          expect(result['content_type']).to eq('application/json')
        end
      end
    end

    describe '#generate_sanitized_filename' do
      let(:import) { create(:import, user: user, name: 'Filename test import') }
      let(:blob) { create_blob(filename: 'test/file<>:"|?*\\.json') }

      before { import.file.attach(blob) }

      it 'sanitizes filename correctly' do
        result = service.send(:generate_sanitized_filename, import)

        expect(result).to eq("import_#{import.id}_test-file--------.json")
      end
    end

    describe '#add_file_metadata_to_import' do
      let(:import) { create(:import, user: user) }
      let(:import_hash) { {} }
      let(:filename) { 'sanitized_filename.json' }
      let(:blob) { create_blob(filename: 'original.json', content_type: 'application/json') }

      before { import.file.attach(blob) }

      it 'adds correct metadata to import hash' do
        service.send(:add_file_metadata_to_import, import, import_hash, filename)

        expect(import_hash).to include(
          'file_name' => 'sanitized_filename.json',
          'original_filename' => 'original.json',
          'file_size' => blob.byte_size,
          'content_type' => 'application/json'
        )
      end
    end
  end

  private

  def create_blob(filename: 'test.txt', content_type: 'text/plain')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('test content'),
      filename: filename,
      content_type: content_type
    )
  end
end
