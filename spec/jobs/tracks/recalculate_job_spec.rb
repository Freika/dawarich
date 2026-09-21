# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::RecalculateJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:track) do
      create(:track, user: user).tap do |t|
        2.times { create(:point, user: user).update_column(:track_id, t.id) }
      end
    end

    before do
      allow(ExceptionReporter).to receive(:call)
    end

    it 'recalculates path and distance for the track' do
      expect(Tracks::Recalculator).to receive(:call).with(instance_of(Track))
      described_class.perform_now(track.id)
    end

    it 'uses the Track after-commit broadcast instead of broadcasting twice' do
      expect_any_instance_of(Track).not_to receive(:broadcast_geojson_updated)
      described_class.perform_now(track.id)
    end

    it 'queues in the tracks queue' do
      expect(described_class.new.queue_name).to eq('tracks')
    end

    context 'when every point has left the track' do
      it 'destroys the track instead of storing an empty path' do
        empty_track = create(:track, user: user)

        expect { described_class.perform_now(empty_track.id) }
          .to change { Track.exists?(empty_track.id) }.to(false)
      end
    end

    context 'when a track is left with a single point' do
      it 'destroys it, since one point cannot form a path' do
        thin_track = create(:track, user: user)
        create(:point, user: user).update_column(:track_id, thin_track.id)

        expect { described_class.perform_now(thin_track.id) }
          .to change { Track.exists?(thin_track.id) }.to(false)
      end
    end

    context 'when track does not exist' do
      it 'does not raise error' do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end

      it 'does not attempt to recalculate' do
        expect(Tracks::Recalculator).not_to receive(:call)
        described_class.perform_now(-1)
      end
    end

    context 'when recalculation fails' do
      before do
        allow(Tracks::Recalculator).to receive(:call).and_raise(StandardError, 'Database error')
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
    end
  end
end
