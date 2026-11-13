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

    it 'holds the claim long after the cooldown so a run waiting behind a queue is not doubled' do
      Geocoding::Cooldown.start(config)
      described_class.schedule(config)

      ttl = Sidekiq.redis { |redis| redis.call('TTL', described_class::CLAIM_KEY) }
      expect(ttl).to be > 1.hour.to_i
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

      context 'with a backlog larger than one batch' do
        before { stub_const('Points::ResumeReverseGeocodingJob::BATCH_SIZE', 1) }

        it 'queues one batch and leaves the rest to a run behind it' do
          described_class.perform_now

          expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', second_point.id, force: false).once
          expect(ReverseGeocodingJob).not_to have_been_enqueued.with('Point', third_point.id, force: false)
          expect(described_class).to have_been_enqueued.with(second_point.id).once
        end

        it 'carries on after the last batch it queued' do
          expect { described_class.perform_now(second_point.id) }
            .to have_enqueued_job(ReverseGeocodingJob).with('Point', third_point.id, force: false)
        end

        it 'stops queueing when a cooldown started during the last batch' do
          Geocoding::Cooldown.start(config)

          described_class.perform_now(second_point.id)

          expect(ReverseGeocodingJob).not_to have_been_enqueued
          expect(described_class).to have_been_enqueued.once
        end
      end

      it 'does not queue a point another job already holds' do
        Point.claim_geocode_ids([third_point.id])

        described_class.perform_now

        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', second_point.id, force: false).once
        expect(ReverseGeocodingJob).not_to have_been_enqueued.with('Point', third_point.id, force: false)
      end

      it 'releases its claims when the jobs cannot be queued' do
        allow(ActiveJob).to receive(:perform_all_later).and_raise(RedisClient::CannotConnectError, 'redis down')

        expect { described_class.perform_now }.to raise_error(RedisClient::CannotConnectError)

        expect(Point.claim_geocode_ids([second_point.id])).to eq([second_point.id])
      end
    end

    context 'when the last refusal has not been answered by the provider yet' do
      let(:cached) { double(city: 'Berlin', country: 'Germany', data: { 'properties' => {} }, cache_hit: true) }
      let(:answered) { double(city: 'Berlin', country: 'Germany', data: { 'properties' => {} }, cache_hit: false) }

      before do
        Geocoding::Cooldown.start(config)
        expire_geocoding_cooldown
      end

      it 'queues the backlog anyway when the probe ends on cached answers' do
        stub_const('Points::ResumeReverseGeocodingJob::PROBE_LIMIT', 1)
        allow(Geocoder).to receive(:search).and_return([cached])

        described_class.perform_now

        expect(first_point.reload.reverse_geocoded_at).to be_present
        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', second_point.id, force: false).once
        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', third_point.id, force: false).once
      end

      it 'keeps probing until the provider itself answers' do
        allow(Geocoder).to receive(:search).and_return([cached], [answered])

        described_class.perform_now

        expect(Geocoder).to have_received(:search).twice
        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', third_point.id, force: false).once
      end

      it 'moves past a point whose lookup stays an error answer' do
        error = double(city: nil, country: nil, data: { 'error' => 'Unable to geocode' }, cache_hit: true)
        allow(Geocoder).to receive(:search).and_return([error], [answered])

        described_class.perform_now

        expect(first_point.reload.reverse_geocoded_at).to be_nil
        expect(second_point.reload.reverse_geocoded_at).to be_present
        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', third_point.id, force: false).once
      end
    end

    context 'when forced lookups were skipped during a cooldown' do
      let(:answered) { double(city: 'Berlin', country: 'Germany', data: { 'properties' => {} }, cache_hit: false) }

      def skip_forced_lookup(point)
        ReverseGeocoding::Points::FetchData.new(point.id, force: true).call
      end

      def forced_lookup(point)
        ['Point', point.id, { force: true }]
      end

      before do
        allow(Geocoder).to receive(:search).and_return([answered])
        Point.update_all(reverse_geocoded_at: 1.day.ago)
        Geocoding::Cooldown.start(config)
      end

      it 'queues the forced run again from the lowest skipped point of that user' do
        skip_forced_lookup(third_point)
        skip_forced_lookup(second_point)
        Geocoding::Cooldown.reset!

        described_class.perform_now(0)

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(second_point)).once
        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(third_point)).once
        expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(first_point))
      end

      it 'drops waiting forced runs on a hosted instance that now uses a paid provider' do
        skip_forced_lookup(first_point)
        Geocoding::Cooldown.reset!
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        allow(Geocoding::Providers).to receive(:api_key_required?).and_return(true)

        described_class.perform_now

        expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(first_point))
        expect(Geocoder).not_to have_received(:search)
        expect(Sidekiq.redis { |r| r.call('ZCARD', described_class::FORCED_RUNS_KEY) }).to eq(0)
      end

      it 'walks the run in capped batches until it runs out of points' do
        stub_const('Points::ResumeReverseGeocodingJob::BATCH_SIZE', 1)
        skip_forced_lookup(first_point)
        Geocoding::Cooldown.reset!

        described_class.perform_now(0)

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(first_point)).once
        expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(second_point))

        3.times { described_class.perform_now(0) }

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(second_point)).once
        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(third_point)).once
        expect(described_class).to have_been_enqueued.exactly(3).times
        expect { described_class.perform_now(0) }.not_to have_enqueued_job
      end

      it 'waits out a second cooldown and carries on from the point it skipped' do
        stub_const('Points::ResumeReverseGeocodingJob::BATCH_SIZE', 1)
        skip_forced_lookup(first_point)
        Geocoding::Cooldown.reset!
        described_class.perform_now(0)

        Geocoding::Cooldown.start(config)
        skip_forced_lookup(first_point)

        expect { described_class.perform_now(0) }.to have_enqueued_job(described_class)
        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(first_point)).once

        Geocoding::Cooldown.reset!
        described_class.perform_now(0)

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(first_point)).twice
      end

      it 'takes the next user once the first run is queued' do
        other_point = create(:point, user: create(:user), reverse_geocoded_at: 1.day.ago)
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        skip_forced_lookup(third_point)
        skip_forced_lookup(other_point)
        Geocoding::Cooldown.reset!

        described_class.perform_now(0)

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(third_point)).once
        expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(other_point))

        described_class.perform_now(0)

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(other_point)).once
      end

      it 'also carries on from a forced lookup the provider itself refused' do
        Geocoding::Cooldown.reset!
        allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError)
        allow(ExceptionReporter).to receive(:call)
        skip_forced_lookup(second_point)
        allow(Geocoder).to receive(:search).and_return([answered])
        Geocoding::Cooldown.reset!

        described_class.perform_now(0)

        expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(second_point)).once
      end

      it 'does not start a forced run for a point the backlog already covers' do
        first_point.reload.update_columns(reverse_geocoded_at: nil)
        skip_forced_lookup(first_point)
        Geocoding::Cooldown.reset!

        described_class.perform_now

        expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(first_point))
      end

      context 'when the original queue answered some of the run' do
        def answer_forced_lookup(point)
          Geocoding::Cooldown.reset!
          ReverseGeocoding::Points::FetchData.new(point.id, force: true).call
        end

        it 'does not send those points again' do
          skip_forced_lookup(first_point)
          answer_forced_lookup(second_point)

          described_class.perform_now(0)

          expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(first_point)).once
          expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(third_point)).once
          expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(second_point))
        end

        it 'keeps the time of the first skip when later skips lower the cursor' do
          skip_forced_lookup(third_point)
          answer_forced_lookup(second_point)
          Geocoding::Cooldown.start(config)
          skip_forced_lookup(first_point)
          Geocoding::Cooldown.reset!

          described_class.perform_now(0)

          expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(first_point)).once
          expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(second_point))
        end

        it 'starts the next run from its own first skip once this one has ended' do
          skip_forced_lookup(first_point)
          Geocoding::Cooldown.reset!
          described_class.perform_now(0)
          answer_forced_lookup(second_point)
          ActiveJob::Base.queue_adapter.enqueued_jobs.clear

          Geocoding::Cooldown.start(config)
          skip_forced_lookup(first_point)
          Geocoding::Cooldown.reset!
          described_class.perform_now(0)

          expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(second_point)).once
        end
      end

      context 'when the provider answers while a run waits' do
        let(:forced_run_keys) { [described_class::FORCED_RUNS_KEY, described_class::FORCED_RUN_STARTS_KEY] }

        def seconds_left
          Sidekiq.redis { |redis| forced_run_keys.map { |key| redis.call('TTL', key) } }
        end

        before do
          skip_forced_lookup(first_point)
          Geocoding::Cooldown.reset!
          Sidekiq.redis { |redis| forced_run_keys.each { |key| redis.call('EXPIRE', key, 60) } }
        end

        it 'renews the expiry before the walk has started' do
          Geocoding::RateLimiter.throttle(config) { [answered] }

          expect(seconds_left).to all(be > 1.day.to_i)
        end

        it 'leaves the expiry alone for a cached answer' do
          Geocoding::RateLimiter.throttle(config) { [double(cache_hit: true)] }

          expect(seconds_left).to all(be <= 60)
        end
      end

      context 'with no backlog to probe the provider on' do
        before do
          skip_forced_lookup(first_point)
          Geocoding::Cooldown.reset!
        end

        it 'looks up the first point of the run itself and does not queue it again' do
          described_class.perform_now

          expect(Geocoder).to have_received(:search).once
          expect(first_point.reload.reverse_geocoded_at).to be_within(1.minute).of(Time.current)
          expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(first_point))
          expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(second_point)).once
          expect(ReverseGeocodingJob).to have_been_enqueued.with(*forced_lookup(third_point)).once
        end

        it 'queues nothing but the next attempt when the provider still refuses' do
          allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError)
          allow(ExceptionReporter).to receive(:call)

          described_class.perform_now

          expect(Geocoder).to have_received(:search).once
          expect(ReverseGeocodingJob).not_to have_been_enqueued
          expect(described_class).to have_been_enqueued.once
        end
      end

      it 'drops a run the provider has not answered for the whole expiry' do
        skip_forced_lookup(first_point)
        expire_forced_runs
        Geocoding::Cooldown.reset!

        described_class.perform_now

        expect(ReverseGeocodingJob).not_to have_been_enqueued.with(*forced_lookup(first_point))
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
