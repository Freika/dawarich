# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::ReArchiveMonthJob, type: :job do
  describe '#perform' do
    let(:archiver) { instance_double(Points::RawData::Archiver) }
    let(:user_id) { 123 }
    let(:year) { 2024 }
    let(:month) { 6 }

    before do
      allow(Points::RawData::Archiver).to receive(:new).and_return(archiver)
    end

    it 'calls archive_specific_month with correct parameters' do
      expect(archiver).to receive(:archive_specific_month).with(user_id, year, month)

      described_class.perform_now(user_id, year, month)
    end

    context 'when re-archival fails' do
      before do
        allow(archiver).to receive(:archive_specific_month).and_raise(StandardError, 'Re-archive failed')
      end

      it 're-raises the error' do
        expect do
          described_class.perform_now(user_id, year, month)
        end.to raise_error(StandardError, 'Re-archive failed')
      end
    end
  end
end
