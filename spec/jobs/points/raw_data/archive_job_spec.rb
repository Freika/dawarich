# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ArchiveJob, type: :job do
  describe '#perform' do
    let(:archiver) { instance_double(Points::RawData::Archiver) }

    before do
      allow(Points::RawData::Archiver).to receive(:new).and_return(archiver)
    end

    it 'calls the archiver service' do
      expect(archiver).to receive(:call).and_return({ processed: 5, archived: 100, failed: 0 })

      described_class.perform_now
    end

    context 'when archiver raises an error' do
      before do
        allow(archiver).to receive(:call).and_raise(StandardError, 'Archive failed')
      end

      it 're-raises the error' do
        expect do
          described_class.perform_now
        end.to raise_error(StandardError, 'Archive failed')
      end
    end
  end
end
