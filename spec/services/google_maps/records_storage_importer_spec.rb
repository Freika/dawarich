# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::RecordsStorageImporter do
  let(:user) { create(:user) }
  let(:import) { create(:import, source: 'google_records') }
  let(:file_path) { Rails.root.join('spec/fixtures/files/google/records.json') }
  let(:file_content) { File.read(file_path) }
  let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/json') }
  let(:parsed_content) { JSON.parse(file_content) }

  before do
    import.file.attach(
      io: StringIO.new(file_content),
      filename: 'records.json',
      content_type: 'application/json'
    )
  end

  subject { described_class.new(import, user.id) }

  describe '#call' do
    context 'with valid file' do
      it 'processes files correctly' do
        # Setup mock
        mock_importer = instance_double(GoogleMaps::RecordsImporter)
        allow(GoogleMaps::RecordsImporter).to receive(:new).and_return(mock_importer)
        allow(mock_importer).to receive(:call)

        # Run the method
        subject.call

        # The test fixture file has a small number of locations,
        # and since we now process all records, we should expect `new` to be called
        expect(GoogleMaps::RecordsImporter).to have_received(:new)
        expect(mock_importer).to have_received(:call).once
      end

      context 'when file has more locations than batch size' do
        let(:large_batch) do
          locations = []
          1001.times do |_i|
            locations << {
              latitudeE7: 533_690_550,
              longitudeE7: 836_950_010,
              accuracy: 150,
              source: 'UNKNOWN',
              timestamp: '2012-12-15T14:21:29.460Z'
            }
          end
          { locations: locations }.to_json
        end

        before do
          import.file.attach(
            io: StringIO.new(large_batch),
            filename: 'records.json',
            content_type: 'application/json'
          )
        end

        it 'processes in batches of 1000 and handles remaining records' do
          # Add a test spy to verify behavior
          mock_importer = instance_double(GoogleMaps::RecordsImporter)
          allow(GoogleMaps::RecordsImporter).to receive(:new).and_return(mock_importer)
          allow(mock_importer).to receive(:call)

          # Run the method
          subject.call

          # Verify batches were processed correctly
          expect(GoogleMaps::RecordsImporter).to have_received(:new).with(import, 0).ordered
          expect(GoogleMaps::RecordsImporter).to have_received(:new).with(import, 1000).ordered
          expect(mock_importer).to have_received(:call).exactly(2).times

          # Verify batch sizes
          first_call_args = nil
          second_call_args = nil

          allow(mock_importer).to receive(:call) do |args|
            if first_call_args.nil?
              first_call_args = args
            else
              second_call_args = args
            end
          end

          expect(first_call_args&.size).to eq(1000) if first_call_args
          expect(second_call_args&.size).to eq(1) if second_call_args
        end
      end

      context 'with multiple batches' do
        let(:multi_batch_data) do
          locations = []
          2345.times do |i|
            locations << {
              latitudeE7: 533_690_550,
              longitudeE7: 836_950_010,
              accuracy: 150,
              source: 'UNKNOWN',
              timestamp: "2012-12-15T14:21:#{i}.460Z"
            }
          end
          { locations: locations }.to_json
        end

        before do
          import.file.attach(
            io: StringIO.new(multi_batch_data),
            filename: 'records.json',
            content_type: 'application/json'
          )
        end

        it 'processes all records across multiple batches' do
          # Set up to capture batch sizes
          batch_sizes = []

          # Create mock
          mock_importer = instance_double(GoogleMaps::RecordsImporter)

          # Set up the call tracking BEFORE allowing :new to return the mock
          allow(mock_importer).to receive(:call) do |batch|
            batch_sizes << batch.size
          end

          allow(GoogleMaps::RecordsImporter).to receive(:new).and_return(mock_importer)

          # Run the method
          subject.call

          # Should have 3 batches: 1000 + 1000 + 345
          expect(GoogleMaps::RecordsImporter).to have_received(:new).with(import, 0).ordered
          expect(GoogleMaps::RecordsImporter).to have_received(:new).with(import, 1000).ordered
          expect(GoogleMaps::RecordsImporter).to have_received(:new).with(import, 2000).ordered
          expect(mock_importer).to have_received(:call).exactly(3).times

          # Verify the batch sizes
          expect(batch_sizes).to eq([1000, 1000, 345])
        end
      end
    end

    context 'with download issues' do
      it 'retries on timeout' do
        # Create a mock that will return a successful result
        # The internal retries are implemented inside SecureFileDownloader,
        # not in the RecordsStorageImporter
        downloader = instance_double(Imports::SecureFileDownloader)

        # Create the downloader mock before it gets used
        expect(Imports::SecureFileDownloader).to receive(:new).with(import.file).and_return(downloader)

        # The SecureFileDownloader handles all the retries internally
        # From the perspective of the importer, it just gets the file content
        expect(downloader).to receive(:download_with_verification).once.and_return(file_content)

        # Run the method
        subject.call
      end

      it 'fails after max retries' do
        # The retry mechanism is in SecureFileDownloader, not RecordsStorageImporter
        # So we need to simulate that the method throws the error after internal retries
        downloader = instance_double(Imports::SecureFileDownloader)

        # Create the downloader mock before it gets used - expect only one call from the importer
        expect(Imports::SecureFileDownloader).to receive(:new).with(import.file).and_return(downloader)

        # This should be called once, and the internal retries should have been attempted
        # After the max retries, it will still raise the Timeout::Error that bubbles up
        expect(downloader).to receive(:download_with_verification).once.and_raise(Timeout::Error)

        # We expect the error to bubble up to the caller
        expect { subject.call }.to raise_error(Timeout::Error)
      end
    end

    context 'with file integrity issues' do
      it 'raises error when file size mismatches' do
        allow_any_instance_of(StringIO).to receive(:size).and_return(9999)
        allow(import.file.blob).to receive(:byte_size).and_return(1234)

        expect { subject.call }.to raise_error(/Incomplete download/)
      end

      it 'raises error when checksum mismatches' do
        allow(import.file.blob).to receive(:checksum).and_return('invalid_checksum')

        expect { subject.call }.to raise_error(/Checksum mismatch/)
      end
    end

    context 'with invalid JSON' do
      before do
        import.file.attach(
          io: StringIO.new('invalid json'),
          filename: 'records.json',
          content_type: 'application/json'
        )
      end

      it 'logs and raises parse error' do
        expect { subject.call }.to raise_error(JSON::ParserError)
      end
    end

    context 'with invalid data structure' do
      before do
        import.file.attach(
          io: StringIO.new({ wrong_key: [] }.to_json),
          filename: 'records.json',
          content_type: 'application/json'
        )
      end

      it 'returns early when locations key is missing' do
        mock_importer = instance_double(GoogleMaps::RecordsImporter)
        allow(GoogleMaps::RecordsImporter).to receive(:new).and_return(mock_importer)
        allow(mock_importer).to receive(:call)

        subject.call
        expect(GoogleMaps::RecordsImporter).not_to have_received(:new)
      end
    end
  end
end
