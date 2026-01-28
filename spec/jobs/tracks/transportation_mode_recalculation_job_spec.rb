# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TransportationModeRecalculationJob, type: :job do
  let(:user) { create(:user) }
  let!(:track1) { create(:track, user: user) }
  let!(:track2) { create(:track, user: user) }
  let(:status_manager) { Tracks::TransportationRecalculationStatus.new(user.id) }

  describe '#perform' do
    it 'reprocesses all user tracks' do
      expect(Tracks::Reprocessor).to receive(:reprocess).with(track1)
      expect(Tracks::Reprocessor).to receive(:reprocess).with(track2)

      described_class.new.perform(user.id)
    end

    it 'sets completed status when finished' do
      allow(Tracks::Reprocessor).to receive(:reprocess)

      described_class.new.perform(user.id)

      expect(status_manager.current_status).to eq('completed')
    end

    it 'handles non-existent user gracefully' do
      expect { described_class.new.perform(999_999) }.not_to raise_error
    end

    context 'when an error occurs' do
      before do
        allow(Tracks::Reprocessor).to receive(:reprocess).and_raise(StandardError, 'Test error')
      end

      it 'sets failed status with error message' do
        expect { described_class.new.perform(user.id) }.to raise_error(StandardError)

        status = status_manager.data
        expect(status['status']).to eq('failed')
        expect(status['error_message']).to eq('Test error')
      end
    end
  end
end
