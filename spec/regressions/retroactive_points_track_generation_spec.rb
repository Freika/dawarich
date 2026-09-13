# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Retroactive point ingestion schedules historical track generation' do
  let(:user) { create(:user) }

  def params_for(timestamps)
    {
      locations: timestamps.each_with_index.map do |ts, index|
        {
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [13.40 + (index * 0.001), 52.50 + (index * 0.001)] },
          properties: { timestamp: ts.iso8601 }
        }
      end
    }
  end

  context 'when the batch is older than the realtime lookback window' do
    let(:anchor) { Time.zone.local(2024, 6, 15, 10, 0, 0) }
    let(:timestamps) { [anchor, anchor + 5.minutes, anchor + 10.minutes] }

    it 'enqueues a single debounced backfill job' do
      expect { Points::Create.new(user, params_for(timestamps)).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end

    it 'coalesces a burst of retroactive batches into one backfill job' do
      expect do
        Points::Create.new(user, params_for(timestamps)).call
        Points::Create.new(user, params_for([anchor - 1.day])).call
      end.to have_enqueued_job(Tracks::BackfillGenerationJob).exactly(1).times
    end
  end

  context 'when the batch falls within the realtime lookback window' do
    let(:timestamps) { [30.minutes.ago, 25.minutes.ago, 20.minutes.ago] }

    it 'does not enqueue a backfill job' do
      expect { Points::Create.new(user, params_for(timestamps)).call }
        .not_to have_enqueued_job(Tracks::BackfillGenerationJob)
    end
  end

  describe 'all four point creators are wired to the backfill scheduler' do
    it 'enqueues a backfill job from Points::Create' do
      expect { Points::Create.new(user, params_for([Time.zone.local(2024, 6, 15, 10)])).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end

    it 'enqueues a backfill job from OwnTracks::PointCreator' do
      payload = OwnTracks::RecParser.new(File.read('spec/fixtures/files/owntracks/2024-03.rec')).call.first

      expect { OwnTracks::PointCreator.new(payload, user.id).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end

    it 'enqueues a backfill job from Traccar::PointCreator' do
      payload = {
        device_id: 'iphone-frey',
        location: { timestamp: '2024-04-23T12:34:56Z', latitude: 52.52, longitude: 13.405 }
      }

      expect { Traccar::PointCreator.new(payload, user.id).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end

    it 'enqueues a backfill job from Overland::PointsCreator' do
      payload = JSON.parse(File.read('spec/fixtures/files/overland/geodata.json'))

      expect { Overland::PointsCreator.new(payload, user.id).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end
  end

  describe 'the debounced backfill job generates tracks for the accumulated window' do
    let(:anchor) { Time.zone.local(2024, 6, 15, 10, 0, 0) }

    it 'enqueues a scoped bulk generation spanning the affected days' do
      Tracks::BackfillScheduler.new(user.id, [anchor.to_i, (anchor + 2.days).to_i]).call

      expect { Tracks::BackfillGenerationJob.perform_now(user.id) }
        .to have_enqueued_job(Tracks::ParallelGeneratorJob)
        .with(
          user.id,
          hash_including(
            start_at: anchor.beginning_of_day,
            end_at: (anchor + 2.days).end_of_day,
            mode: :bulk,
            untracked_only: true
          )
        )
    end
  end
end
