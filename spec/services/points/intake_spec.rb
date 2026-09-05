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

    it 'writes under the caller, not the user_id a payload carries' do
      other_user = create(:user)
      foreign = payloads.map { |payload| payload.merge(user_id: other_user.id) }

      described_class.call(user_id: user.id, payloads: foreign)

      expect(Point.where(user: other_user)).to be_empty
      expect(Point.where(user:).count).to eq(2)
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

    it 'broadcasts the upserted rows with the payloads they came from' do
      broadcaster = instance_double(Points::LiveBroadcaster, call: nil)
      allow(Points::LiveBroadcaster).to receive(:new).and_return(broadcaster)

      rows = intake

      expect(Points::LiveBroadcaster).to have_received(:new).with(
        user.id,
        rows,
        [hash_including(timestamp: 1_760_000_000), hash_including(timestamp: 1_760_000_060)]
      )
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

    context 'when the upsert returns no rows' do
      before { allow(Point).to receive(:archival_safe_upsert_all).and_return([]) }

      it 'returns an empty array' do
        expect(intake).to eq([])
      end

      it 'enqueues no anomaly filter' do
        expect { intake }.not_to have_enqueued_job(Points::AnomalyFilterJob)
      end
    end
  end

  describe 'bulk intake' do
    subject(:bulk_intake) { described_class.call(user_id: user.id, payloads: payloads, mode: :bulk) }

    it 'persists and counts points without triggering realtime arrival work' do
      allow(Points::LiveBroadcaster).to receive(:new)
      allow(Tracks::RealtimeDebouncer).to receive(:new)
      allow(Tracks::BackfillScheduler).to receive(:new)
      allow(Visits::RealtimeDebouncer).to receive(:new)

      expect { bulk_intake }
        .to change { user.points.count }.by(2)
        .and change { user.reload.points_count }.by(2)

      expect(Points::AnomalyFilterJob).not_to have_been_enqueued
      expect(Points::LiveBroadcaster).not_to have_received(:new)
      expect(Tracks::RealtimeDebouncer).not_to have_received(:new)
      expect(Tracks::BackfillScheduler).not_to have_received(:new)
      expect(Visits::RealtimeDebouncer).not_to have_received(:new)
    end
  end

  def many_payloads(count)
    Array.new(count) do |i|
      { lonlat: "POINT(#{13.4 + (i / 100_000.0)} 52.5)", timestamp: 1_760_000_000 + i, tracker_id: 'bulk' }
    end
  end
end
