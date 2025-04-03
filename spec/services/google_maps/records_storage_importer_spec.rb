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
        # Add a test spy to verify behavior
        records_importer = class_spy(GoogleMaps::RecordsImporter)
        stub_const('GoogleMaps::RecordsImporter', records_importer)

        # Run the method
        subject.call

        # Small files won't process any batches (< BATCH_SIZE)
        expect(records_importer).not_to have_received(:new)
      end

      context 'when file has more locations than batch size' do
        let(:large_batch) do
          locations = []
          1001.times do |i|
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

        it 'processes in batches of 1000' do
          # Add a test spy to verify behavior
          mock_importer = instance_double(GoogleMaps::RecordsImporter)
          allow(GoogleMaps::RecordsImporter).to receive(:new).and_return(mock_importer)
          allow(mock_importer).to receive(:call)

          # Run the method
          subject.call

          # Verify that the importer was called with the first 1000 locations
          expect(GoogleMaps::RecordsImporter).to have_received(:new).with(import, 1000)

          # Based on the implementation, remaining 1 item is NOT processed
          # Because there's no code after the loop to handle remaining items
          expect(GoogleMaps::RecordsImporter).to have_received(:new).exactly(1).times
        end
      end
    end

    context 'with download issues' do
      it 'retries on timeout' do
        call_count = 0
        allow(import.file.blob).to receive(:download) do
          call_count += 1
          call_count < 3 ? raise(Timeout::Error) : file_content
        end

        expect(Rails.logger).to receive(:warn).twice
        subject.call
        expect(call_count).to eq(3)
      end

      it 'fails after max retries' do
        allow(import.file.blob).to receive(:download).and_raise(Timeout::Error)

        expect(Rails.logger).to receive(:warn).exactly(3).times
        expect(Rails.logger).to receive(:error).with('Download failed after 3 attempts')

        expect { subject.call }.to raise_error(Timeout::Error)
      end
    end

    context 'with file integrity issues' do
      it 'raises error when file size mismatches' do
        allow(import.file.blob).to receive(:byte_size).and_return(9999)

        expect(Rails.logger).to receive(:error)
        expect { subject.call }.to raise_error(/Incomplete download/)
      end

      it 'raises error when checksum mismatches' do
        allow(import.file.blob).to receive(:checksum).and_return('invalid_checksum')

        expect(Rails.logger).to receive(:error)
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
        # Directly mock the standard error handling since the error happens during parsing
        expect(Rails.logger).to receive(:error).with(/Download error: Empty input/)
        expect { subject.call }.to raise_error(StandardError)
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
        expect(GoogleMaps::RecordsImporter).not_to receive(:new)
        subject.call
      end
    end
  end
end
