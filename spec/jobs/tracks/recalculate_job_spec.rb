# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::RecalculateJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user) }

    before do
      allow(ExceptionReporter).to receive(:call)
    end

    it 'recalculates path and distance for the track' do
      expect_any_instance_of(Track).to receive(:recalculate_path_and_distance!)
      described_class.perform_now(track.id)
    end

    it 'broadcasts updated track GeoJSON via ActionCable' do
      allow_any_instance_of(Track).to receive(:recalculate_path_and_distance!)
      expect_any_instance_of(Track).to receive(:broadcast_geojson_updated)
      described_class.perform_now(track.id)
    end

    it 'queues in the tracks queue' do
      expect(described_class.new.queue_name).to eq('tracks')
    end

    context 'when track does not exist' do
      it 'does not raise error' do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end

      it 'does not attempt to recalculate' do
        expect_any_instance_of(Track).not_to receive(:recalculate_path_and_distance!)
        described_class.perform_now(-1)
      end
    end

    context 'when recalculation fails' do
      before do
        allow_any_instance_of(Track).to receive(:recalculate_path_and_distance!)
          .and_raise(StandardError, 'Database error')
      end

      it 'does not raise error' do
        expect { described_class.perform_now(track.id) }.not_to raise_error
      end

      it 'reports the exception' do
        described_class.perform_now(track.id)
        expect(ExceptionReporter).to have_received(:call).with(
          instance_of(StandardError),
          "Failed to recalculate track #{track.id}"
        )
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Failed to recalculate track #{track.id}/)
        described_class.perform_now(track.id)
      end
    end

    context 'when broadcast fails' do
      before do
        allow_any_instance_of(Track).to receive(:recalculate_path_and_distance!)
        allow_any_instance_of(Track).to receive(:broadcast_geojson_updated)
          .and_raise(StandardError, 'Redis connection failed')
      end

      it 'does not raise error' do
        expect { described_class.perform_now(track.id) }.not_to raise_error
      end

      it 'reports the exception' do
        described_class.perform_now(track.id)
        expect(ExceptionReporter).to have_received(:call)
      end
    end
  end
end
