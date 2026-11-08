# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::ResumeReverseGeocodingJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:config) { Geocoding::Config.resolved_config }

  before do
    configure_instance_geocoding
    Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe '.schedule' do
    it 'does nothing while lookups are not paused' do
      expect { described_class.schedule(config) }.not_to have_enqueued_job(described_class)
    end

    it 'schedules a run for when the cooldown ends' do
      Geocoding::Cooldown.start(config)

      freeze_time do
        expect { described_class.schedule(config) }
          .to have_enqueued_job(described_class)
          .at(a_value_within(5.seconds).of(Geocoding::Cooldown::BASE_DURATION.from_now))
      end
    end

    it 'schedules one run however many skipped lookups ask for it' do
      Geocoding::Cooldown.start(config)

      expect { 3.times { described_class.schedule(config) } }.to have_enqueued_job(described_class).once
    end
  end

  describe '#perform' do
    let!(:first_point) { create(:point, user:, reverse_geocoded_at: nil) }
    let!(:second_point) { create(:point, user:, reverse_geocoded_at: nil) }
    let!(:third_point) { create(:point, user:, reverse_geocoded_at: nil) }

    # Creating a point queues its own lookup; start from a backlog nobody has
    # queued yet, as after a cooldown skipped every queued lookup.
    before do
      Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    context 'when the provider answers again' do
      before do
        allow(Geocoder).to receive(:search).and_return(
          [double(city: 'Berlin', country: 'Germany', data: { 'properties' => {} })]
        )
      end

      it 'geocodes one point and queues the rest of the backlog' do
        expect { described_class.perform_now }
          .to have_enqueued_job(ReverseGeocodingJob).with('Point', second_point.id, force: false)
          .and have_enqueued_job(ReverseGeocodingJob).with('Point', third_point.id, force: false)

        expect(first_point.reload.reverse_geocoded_at).to be_present
      end

      it 'can be scheduled again after it has run' do
        described_class.perform_now
        Geocoding::Cooldown.start(config)

        expect { described_class.schedule(config) }.to have_enqueued_job(described_class)
      end
    end

    context 'when the provider still refuses' do
      before { allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError) }

      it 'sends a single lookup and queues nothing but the next attempt' do
        described_class.perform_now

        expect(described_class).to have_been_enqueued.once
        expect(ReverseGeocodingJob).not_to have_been_enqueued
        expect(Geocoder).to have_received(:search).once
        expect(first_point.reload.reverse_geocoded_at).to be_nil
      end
    end

    context 'when the cooldown was extended meanwhile' do
      before do
        allow(Geocoder).to receive(:search).and_call_original
        Geocoding::Cooldown.start(config)
      end

      it 'waits for it without asking the provider' do
        described_class.perform_now

        expect(described_class).to have_been_enqueued.once
        expect(ReverseGeocodingJob).not_to have_been_enqueued
        expect(Geocoder).not_to have_received(:search)
      end
    end

    it 'does nothing once the backlog is empty' do
      Point.update_all(reverse_geocoded_at: Time.current)

      expect { described_class.perform_now }.not_to have_enqueued_job
    end

    it 'does nothing when reverse geocoding has been turned off' do
      InstanceSetting.delete_all
      InstanceSettings::Resolver.reset!

      expect { described_class.perform_now }.not_to have_enqueued_job
      expect(first_point.reload.reverse_geocoded_at).to be_nil
    end
  end
end
