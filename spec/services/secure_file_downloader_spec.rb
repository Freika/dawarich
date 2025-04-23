# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecureFileDownloader do
  let(:file_content) { 'test content' }
  let(:file_size) { file_content.bytesize }
  let(:checksum) { Base64.strict_encode64(Digest::MD5.digest(file_content)) }
  let(:blob) { double('ActiveStorage::Blob', byte_size: file_size, checksum: checksum) }
  # Create a mock that mimics ActiveStorage::Attached::One
  let(:storage_attachment) { double('ActiveStorage::Attached::One', blob: blob) }

  subject { described_class.new(storage_attachment) }

  describe '#download_with_verification' do
    context 'when download is successful' do
      before do
        # Mock the download method to yield the file content
        allow(storage_attachment).to receive(:download) do |&block|
          block.call(file_content)
        end
      end

      it 'returns the file content' do
        expect(subject.download_with_verification).to eq(file_content)
      end
    end

    context 'when timeout occurs but succeeds on retry' do
      it 'retries the download internally and returns success after retries' do
        call_count = 0

        # Mock storage_attachment to fail twice then succeed
        allow(storage_attachment).to receive(:download) do |&block|
          call_count += 1
          raise Timeout::Error if call_count < 3

          block.call(file_content)
        end

        # Expect logging for each retry attempt
        expect(Rails.logger).to receive(:warn).with(/Download timeout, attempt 1 of/).ordered
        expect(Rails.logger).to receive(:warn).with(/Download timeout, attempt 2 of/).ordered

        # The method should eventually return the content
        result = subject.download_with_verification
        expect(result).to eq(file_content)
        expect(call_count).to eq(3) # Verify retry attempts
      end
    end

    context 'when all download attempts timeout' do
      it 'raises the error after max retries' do
        # Make download always raise Timeout::Error
        allow(storage_attachment).to receive(:download).and_raise(Timeout::Error)

        # Expect warnings for each retry
        described_class::MAX_RETRIES.times do |i|
          expect(Rails.logger).to receive(:warn).with(/Download timeout, attempt #{i + 1} of/).ordered
        end

        # Expect error log on final failure
        expect(Rails.logger).to receive(:error).with(/Download failed after/).ordered

        # It should raise the Timeout::Error
        expect { subject.download_with_verification }.to raise_error(Timeout::Error)
      end
    end

    context 'when file size does not match' do
      let(:blob) { double('ActiveStorage::Blob', byte_size: 100, checksum: checksum) }

      before do
        allow(storage_attachment).to receive(:download) do |&block|
          block.call(file_content)
        end
      end

      it 'raises an error' do
        expect { subject.download_with_verification }.to raise_error(/Incomplete download/)
      end
    end

    context 'when checksum does not match' do
      let(:blob) { double('ActiveStorage::Blob', byte_size: file_size, checksum: 'invalid_checksum') }

      before do
        allow(storage_attachment).to receive(:download) do |&block|
          block.call(file_content)
        end
      end

      it 'raises an error' do
        expect { subject.download_with_verification }.to raise_error(/Checksum mismatch/)
      end
    end

    context 'when download fails with a different error' do
      before do
        allow(storage_attachment).to receive(:download).and_raise(StandardError, 'Download failed')
      end

      it 'logs the error and re-raises it' do
        expect(Rails.logger).to receive(:error).with(/Download error: Download failed/)
        expect { subject.download_with_verification }.to raise_error(StandardError, 'Download failed')
      end
    end
  end
end
