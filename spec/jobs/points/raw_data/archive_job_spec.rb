# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ArchiveJob, type: :job do
  describe '#perform' do
    let(:archiver) { instance_double(Points::RawData::Archiver) }

    before do
      # Enable archival for tests
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ARCHIVE_RAW_DATA').and_return('true')

      allow(Points::RawData::Archiver).to receive(:new).and_return(archiver)
      allow(archiver).to receive(:call).and_return({ processed: 5, archived: 100, failed: 0 })
    end

    it 'calls the archiver service' do
      expect(archiver).to receive(:call)

      described_class.perform_now
    end

    context 'when archiver raises an error' do
      let(:error) { StandardError.new('Archive failed') }

      before do
        allow(archiver).to receive(:call).and_raise(error)
      end

      it 're-raises the error' do
        expect do
          described_class.perform_now
        end.to raise_error(StandardError, 'Archive failed')
      end

      it 'reports the error before re-raising' do
        expect(ExceptionReporter).to receive(:call).with(error, 'Points raw data archival job failed')

        expect do
          described_class.perform_now
        end.to raise_error(StandardError)
      end
    end
  end
end
