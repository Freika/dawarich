# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Intake do
  subject(:intake) { described_class.call(user_id: user.id, payloads: payloads) }

  let(:user) { create(:user) }
  let(:payloads) do
    [
      { lonlat: 'POINT(13.4050 52.5200)', timestamp: 1_760_000_000, tracker_id: 'pixel-8' },
      { lonlat: 'POINT(13.4060 52.5210)', timestamp: 1_760_000_060, tracker_id: 'pixel-8' }
    ]
  end

  describe 'writing points' do
    it 'persists every usable payload' do
      expect { intake }.to change { Point.where(user:).count }.by(2)
    end

    it 'returns the upserted rows with their coordinates' do
      expect(intake.first).to include('id', 'timestamp', 'longitude', 'latitude')
    end

    it 'stamps user_id onto payloads that arrive without one' do
      intake

      expect(Point.where(user_id: user.id).count).to eq(2)
    end

    it 'stamps the dimension FK as it writes' do
      intake

      expect(user.points.where(source_id: nil)).to be_empty
    end

    it 'writes in slices so a large batch stays bounded' do
      allow(Point).to receive(:archival_safe_upsert_all).and_call_original
      described_class.call(user_id: user.id, payloads: many_payloads(1_500))

      expect(Point).to have_received(:archival_safe_upsert_all).twice
    end
  end

  describe 'rejecting unusable payloads' do
    context 'when a payload has no lonlat' do
      let(:payloads) { [{ lonlat: nil, timestamp: 1_760_000_000 }] }

      it 'drops it' do
        expect { intake }.not_to(change { Point.where(user:).count })
      end
    end

    context 'when a payload has no timestamp' do
      let(:payloads) { [{ lonlat: 'POINT(13.4 52.5)', timestamp: nil }] }

      it 'drops it' do
        expect { intake }.not_to(change { Point.where(user:).count })
      end
    end

    context 'when a payload sits at Null Island' do
      let(:payloads) { [{ lonlat: 'POINT(0.0 0.0)', timestamp: 1_760_000_000 }] }

      it 'drops it' do
        expect { intake }.not_to(change { Point.where(user:).count })
      end

      it 'returns an empty array' do
        expect(intake).to eq([])
      end
    end

    context 'when the batch is entirely nils' do
      let(:payloads) { [nil, nil] }

      it 'returns an empty array' do
        expect(intake).to eq([])
      end
    end

    context 'when the same point arrives twice in one batch' do
      let(:payloads) do
        [
          { lonlat: 'POINT(13.4050 52.5200)', timestamp: 1_760_000_000, tracker_id: 'a' },
          { lonlat: 'POINT(13.4050 52.5200)', timestamp: 1_760_000_000, tracker_id: 'a' }
        ]
      end

      it 'writes it once' do
        expect { intake }.to change { Point.where(user:).count }.by(1)
      end
    end
  end

  describe 'the points counter' do
    it 'counts genuinely inserted rows' do
      intake

      expect(user.reload.points_count).to eq(2)
    end

    it 'does not inflate on resubmission of the same points' do
      intake
      user.reload

      expect { described_class.call(user_id: user.id, payloads: payloads) && user.reload }
        .not_to(change { user.points_count })
    end
  end

  describe 'what follows an arrival' do
    it 'enqueues the anomaly filter over the arrival range' do
      expect { intake }
        .to have_enqueued_job(Points::AnomalyFilterJob)
        .with(user.id, 1_760_000_000, 1_760_000_060)
    end

    it 'triggers the tracks debouncer' do
      debouncer = instance_double(Tracks::RealtimeDebouncer, trigger: nil)
      allow(Tracks::RealtimeDebouncer).to receive(:new).with(user.id).and_return(debouncer)

      intake

      expect(debouncer).to have_received(:trigger)
    end

    it 'schedules the tracks backfill with the arrival timestamps' do
      scheduler = instance_double(Tracks::BackfillScheduler, call: nil)
      allow(Tracks::BackfillScheduler)
        .to receive(:new).with(user.id, [1_760_000_000, 1_760_000_060]).and_return(scheduler)

      intake

      expect(scheduler).to have_received(:call)
    end

    it 'triggers the visits debouncer' do
      debouncer = instance_double(Visits::RealtimeDebouncer, trigger: nil)
      allow(Visits::RealtimeDebouncer).to receive(:new).with(user.id).and_return(debouncer)

      intake

      expect(debouncer).to have_received(:trigger)
    end

    it 'broadcasts the arrival' do
      broadcaster = instance_double(Points::LiveBroadcaster, call: nil)
      allow(Points::LiveBroadcaster).to receive(:new).and_return(broadcaster)

      intake

      expect(broadcaster).to have_received(:call)
    end

    context 'when nothing was written' do
      let(:payloads) { [] }

      it 'enqueues no anomaly filter' do
        expect { intake }.not_to have_enqueued_job(Points::AnomalyFilterJob)
      end

      it 'triggers no debouncer' do
        allow(Tracks::RealtimeDebouncer).to receive(:new)

        intake

        expect(Tracks::RealtimeDebouncer).not_to have_received(:new)
      end
    end
  end

  def many_payloads(count)
    Array.new(count) do |i|
      { lonlat: "POINT(#{13.4 + (i / 100_000.0)} 52.5)", timestamp: 1_760_000_000 + i, tracker_id: 'bulk' }
    end
  end
end
