# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Imports, type: :service do
  let(:user) { create(:user) }
  let(:files_directory) { Rails.root.join('tmp', 'test_files') }
  let(:imports_data) do
    [
      {
        'name' => '2023_MARCH.json',
        'source' => 'google_semantic_history',
        'created_at' => '2024-01-01T00:00:00Z',
        'updated_at' => '2024-01-01T00:00:00Z',
        'processed' => true,
        'file_name' => 'import_1_2023_MARCH.json',
        'original_filename' => '2023_MARCH.json',
        'file_size' => 2048576,
        'content_type' => 'application/json'
      },
      {
        'name' => '2023_APRIL.json',
        'source' => 'owntracks',
        'created_at' => '2024-01-02T00:00:00Z',
        'updated_at' => '2024-01-02T00:00:00Z',
        'processed' => false,
        'file_name' => 'import_2_2023_APRIL.json',
        'original_filename' => '2023_APRIL.json',
        'file_size' => 1048576,
        'content_type' => 'application/json'
      }
    ]
  end
  let(:service) { described_class.new(user, imports_data, files_directory) }

  before do
    FileUtils.mkdir_p(files_directory)
    # Create mock files
    File.write(files_directory.join('import_1_2023_MARCH.json'), '{"test": "data"}')
    File.write(files_directory.join('import_2_2023_APRIL.json'), '{"more": "data"}')
  end

  after do
    FileUtils.rm_rf(files_directory) if files_directory.exist?
  end

  describe '#call' do
    context 'with valid imports data' do
      it 'creates new imports for the user' do
        expect { service.call }.to change { user.imports.count }.by(2)
      end

      it 'creates imports with correct attributes' do
        service.call

        march_import = user.imports.find_by(name: '2023_MARCH.json')
        expect(march_import).to have_attributes(
          name: '2023_MARCH.json',
          source: 'google_semantic_history',
          processed: 1
        )

        april_import = user.imports.find_by(name: '2023_APRIL.json')
        expect(april_import).to have_attributes(
          name: '2023_APRIL.json',
          source: 'owntracks',
          processed: 0
        )
      end

      it 'attaches files to the imports' do
        service.call

        march_import = user.imports.find_by(name: '2023_MARCH.json')
        expect(march_import.file).to be_attached
        expect(march_import.file.filename.to_s).to eq('2023_MARCH.json')
        expect(march_import.file.content_type).to eq('application/json')

        april_import = user.imports.find_by(name: '2023_APRIL.json')
        expect(april_import.file).to be_attached
        expect(april_import.file.filename.to_s).to eq('2023_APRIL.json')
        expect(april_import.file.content_type).to eq('application/json')
      end

      it 'returns the number of imports and files created' do
        imports_created, files_restored = service.call
        expect(imports_created).to eq(2)
        expect(files_restored).to eq(2)
      end

      it 'logs the import process' do
        allow(Rails.logger).to receive(:info) # Allow all info logs (including ActiveStorage)
        expect(Rails.logger).to receive(:info).with("Importing 2 imports for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Imports import completed. Created: 2, Files restored: 2")

        service.call
      end

      it 'does not trigger background processing jobs' do
        expect(Import::ProcessJob).not_to receive(:perform_later)

        service.call
      end

      it 'sets skip_background_processing flag on created imports' do
        service.call

        user.imports.each do |import|
          expect(import.skip_background_processing).to be_truthy
        end
      end
    end

    context 'with duplicate imports' do
      before do
        # Create an existing import with same name, source, and created_at
        user.imports.create!(
          name: '2023_MARCH.json',
          source: 'google_semantic_history',
          created_at: Time.parse('2024-01-01T00:00:00Z')
        )
      end

      it 'skips duplicate imports' do
        expect { service.call }.to change { user.imports.count }.by(1)
      end

      it 'logs when skipping duplicates' do
        allow(Rails.logger).to receive(:debug) # Allow any debug logs
        expect(Rails.logger).to receive(:debug).with("Import already exists: 2023_MARCH.json")

        service.call
      end

      it 'returns only the count of newly created imports' do
        imports_created, files_restored = service.call
        expect(imports_created).to eq(1)
        expect(files_restored).to eq(1)
      end
    end

    context 'with missing files' do
      before do
        FileUtils.rm_f(files_directory.join('import_1_2023_MARCH.json'))
      end

      it 'creates imports but logs file errors' do
        expect(Rails.logger).to receive(:warn).with(/Import file not found/)

        imports_created, files_restored = service.call
        expect(imports_created).to eq(2)
        expect(files_restored).to eq(1) # Only one file was successfully restored
      end

      it 'creates imports without file attachments for missing files' do
        service.call

        march_import = user.imports.find_by(name: '2023_MARCH.json')
        expect(march_import.file).not_to be_attached
      end
    end

    context 'with imports that have no files (null file_name)' do
      let(:imports_data) do
        [
          {
            'name' => 'No File Import',
            'source' => 'gpx',
            'created_at' => '2024-01-01T00:00:00Z',
            'processed' => true,
            'file_name' => nil,
            'original_filename' => nil
          }
        ]
      end

      it 'creates imports without attempting file restoration' do
        expect { service.call }.to change { user.imports.count }.by(1)
      end

      it 'returns correct counts' do
        imports_created, files_restored = service.call
        expect(imports_created).to eq(1)
        expect(files_restored).to eq(0)
      end
    end

    context 'with invalid import data' do
      let(:imports_data) do
        [
          { 'name' => 'Valid Import', 'source' => 'owntracks' },
          'invalid_data',
          { 'name' => 'Another Valid Import', 'source' => 'gpx' }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        expect { service.call }.to change { user.imports.count }.by(2)
      end

      it 'returns the count of valid imports created' do
        imports_created, files_restored = service.call
        expect(imports_created).to eq(2)
        expect(files_restored).to eq(0) # No files for these imports
      end
    end

    context 'with validation errors' do
      let(:imports_data) do
        [
          { 'name' => 'Valid Import', 'source' => 'owntracks' },
          { 'source' => 'owntracks' }, # missing name
          { 'name' => 'Missing Source Import' } # missing source
        ]
      end

      it 'only creates valid imports' do
        expect { service.call }.to change { user.imports.count }.by(2)

        # Verify only the valid imports were created (name is required, source defaults to first enum)
        created_imports = user.imports.pluck(:name, :source)
        expect(created_imports).to contain_exactly(
          ['Valid Import', 'owntracks'],
          ['Missing Source Import', 'google_semantic_history']
        )
      end

      it 'logs validation errors' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        service.call
      end
    end

    context 'with nil imports data' do
      let(:imports_data) { nil }

      it 'does not create any imports' do
        expect { service.call }.not_to change { user.imports.count }
      end

      it 'returns [0, 0]' do
        result = service.call
        expect(result).to eq([0, 0])
      end
    end

    context 'with non-array imports data' do
      let(:imports_data) { 'invalid_data' }

      it 'does not create any imports' do
        expect { service.call }.not_to change { user.imports.count }
      end

      it 'returns [0, 0]' do
        result = service.call
        expect(result).to eq([0, 0])
      end
    end

    context 'with empty imports data' do
      let(:imports_data) { [] }

      it 'does not create any imports' do
        expect { service.call }.not_to change { user.imports.count }
      end

      it 'logs the import process with 0 count' do
        expect(Rails.logger).to receive(:info).with("Importing 0 imports for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Imports import completed. Created: 0, Files restored: 0")

        service.call
      end

      it 'returns [0, 0]' do
        result = service.call
        expect(result).to eq([0, 0])
      end
    end
  end
end
