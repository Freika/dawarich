# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::NightlyReverseGeocodingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      Point.delete_all
      clear_geocode_claims!
    end

    context 'when reverse geocoding is disabled' do
      let!(:point_without_geocoding) do
        create(:point, user: user, reverse_geocoded_at: nil)
      end

      it 'does not process any points' do
        expect(Geocoding::ReverseCommands).not_to receive(:enqueue_points)

        described_class.perform_now
      end

      it 'returns early without querying points' do
        allow(Point).to receive(:not_reverse_geocoded)

        described_class.perform_now

        expect(Point).not_to have_received(:not_reverse_geocoded)
      end

      it 'does not enqueue any ReverseGeocodingJob jobs' do
        expect { described_class.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
      end
    end

    context 'when resolving the geocoding config' do
      before { configure_instance_geocoding }

      it 'resolves the config once per run, not per user or per point' do
        other_user = create(:user)
        create_list(:point, 2, user: user, reverse_geocoded_at: nil)
        create_list(:point, 2, user: other_user, reverse_geocoded_at: nil)
        allow(Geocoding::Config).to receive(:resolved_config).and_call_original

        described_class.perform_now

        expect(Geocoding::Config).to have_received(:resolved_config).once
      end
    end

    context 'when reverse geocoding is enabled' do
      before { configure_instance_geocoding }

      context 'with no points needing reverse geocoding' do
        let!(:geocoded_point) do
          create(:point, user: user, reverse_geocoded_at: 1.day.ago)
        end

        it 'does not process any points' do
          expect(Geocoding::ReverseCommands).not_to receive(:enqueue_points)

          described_class.perform_now
        end

        it 'does not enqueue any ReverseGeocodingJob jobs' do
          expect { described_class.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
        end
      end

      context 'with points needing reverse geocoding' do
        let(:user2) { create(:user) }
        let!(:point_without_geocoding1) do
          create(:point, user: user, reverse_geocoded_at: nil)
        end
        let!(:point_without_geocoding2) do
          create(:point, user: user, reverse_geocoded_at: nil)
        end
        let!(:point_without_geocoding3) do
          create(:point, user: user2, reverse_geocoded_at: nil)
        end
        let!(:geocoded_point) do
          create(:point, user: user, reverse_geocoded_at: 1.day.ago)
        end

        before do
          clear_geocode_claims!
        end

        it 'processes all points that need reverse geocoding' do
          expect { described_class.perform_now }.to have_enqueued_job(ReverseGeocodingJob).exactly(3).times
        end

        it 'enqueues jobs with force: false to preserve the dedup guard' do
          expect { described_class.perform_now }
            .to have_enqueued_job(ReverseGeocodingJob)
            .with('Point', point_without_geocoding1.id, force: false)
            .and have_enqueued_job(ReverseGeocodingJob)
            .with('Point', point_without_geocoding2.id, force: false)
            .and have_enqueued_job(ReverseGeocodingJob)
            .with('Point', point_without_geocoding3.id, force: false)
        end

        it 'keeps pending claims instead of enqueueing duplicates' do
          Sidekiq.redis do |_r|
            [point_without_geocoding1, point_without_geocoding2, point_without_geocoding3].each do |p|
              PhoenixClaims.claim(Point.geocode_dedup_key(p.id), 86_400)
            end
          end

          expect { described_class.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
        end

        it 'uses in_batches with correct batch size' do
          relation_mock = double('ActiveRecord::Relation')
          allow(Point).to receive(:not_reverse_geocoded).and_return(relation_mock)
          allow(relation_mock).to receive(:in_batches).with(of: 1000)

          described_class.perform_now

          expect(relation_mock).to have_received(:in_batches).with(of: 1000)
        end

        it 'invalidates caches for all affected users' do
          allow(Cache::InvalidateUserCaches).to receive(:new).and_call_original

          described_class.perform_now

          # Verify that cache invalidation service was instantiated for both users
          expect(Cache::InvalidateUserCaches).to have_received(:new).with(user.id)
          expect(Cache::InvalidateUserCaches).to have_received(:new).with(user2.id)
        end

        it 'invalidates caches for the correct users' do
          cache_service1 = instance_double(Cache::InvalidateUserCaches)
          cache_service2 = instance_double(Cache::InvalidateUserCaches)

          allow(Cache::InvalidateUserCaches).to receive(:new).with(user.id).and_return(cache_service1)
          allow(Cache::InvalidateUserCaches).to receive(:new).with(user2.id).and_return(cache_service2)
          allow(cache_service1).to receive(:call)
          allow(cache_service2).to receive(:call)

          described_class.perform_now

          expect(cache_service1).to have_received(:call)
          expect(cache_service2).to have_received(:call)
        end

        it 'does not invalidate caches multiple times for the same user' do
          cache_service = instance_double(Cache::InvalidateUserCaches)

          allow(Cache::InvalidateUserCaches).to receive(:new).with(user.id).and_return(cache_service)
          allow(Cache::InvalidateUserCaches).to receive(:new).with(user2.id).and_return(
            instance_double(
              Cache::InvalidateUserCaches, call: nil
            )
          )
          allow(cache_service).to receive(:call)

          described_class.perform_now

          expect(cache_service).to have_received(:call).once
        end
      end
    end

    describe 'Oban-owned sweep' do
      before { configure_instance_geocoding }

      it 'writes per-user batches' do
        job_owner!('command:geocoding.reverse_point', :oban)
        user_a = create(:user)
        user_b = create(:user)
        create_list(:point, 150, user: user_a, reverse_geocoded_at: nil)
        create_list(:point, 30, user: user_b, reverse_geocoded_at: nil)
        allow(Cache::InvalidateUserCaches).to receive(:new).and_call_original

        expect { described_class.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)

        rows = JobOutbox.where(command_type: 'geocoding.reverse_point').order(:created_at)
        expect(rows.map { |r| [r.payload['user_id'], r.payload['point_ids'].size] })
          .to contain_exactly([user_a.id, 100], [user_a.id, 50], [user_b.id, 30])
        expect(rows.map { |r| r.payload['force'] }.uniq).to eq([false])
        expect(Cache::InvalidateUserCaches).to have_received(:new).with(user_a.id).once
        expect(Cache::InvalidateUserCaches).to have_received(:new).with(user_b.id).once
      end
    end

    it 'Rails nightly cron stops batches after Oban claim and resumes after pinned Sidekiq release ' \
       'with invalidation intact' do
      configure_instance_geocoding
      points = Array.new(1001) do |index|
        { user_id: user.id, timestamp: 1_791_115_200 + index, lonlat: 'POINT(13 52)',
          reverse_geocoded_at: nil, created_at: Time.current, updated_at: Time.current }
      end
      Point.insert_all!(points)
      job_owner!('cron:nightly_reverse_geocoding_job', :oban)
      allow(Cache::InvalidateUserCaches).to receive(:new).and_call_original
      described_class.new.perform
      expect(enqueued_jobs.size).to eq(0)
      expect(Cache::InvalidateUserCaches).not_to have_received(:new)
      JobOwnership.release!('cron:nightly_reverse_geocoding_job', by: 'a12d3-test')
      batches = 0
      allow(Geocoding::NightlyCommands).to receive(:enqueue_points).and_wrap_original do |original, *args|
        batches += 1
        result = original.call(*args)
        job_owner!('cron:nightly_reverse_geocoding_job', :oban) if batches == 1
        result
      end
      source = described_class.new
      source.enqueued_at = Time.utc(2026, 10, 4, 1, 15)
      source.perform
      RailsCommands::Poller.drain_once
      expect(enqueued_jobs.size).to eq(1000)
      expect(enqueued_jobs.map { ActiveJob::Arguments.deserialize(_1[:args]).last }).to all(eq(force: false))
      expect(Cache::InvalidateUserCaches).to have_received(:new).with(user.id, year: nil).once
      JobOwnership.release!('cron:nightly_reverse_geocoding_job', by: 'a12d3-test')
      source.perform
      RailsCommands::Poller.drain_once
      expect(enqueued_jobs.size).to eq(1001)
      expect(Cache::InvalidateUserCaches).to have_received(:new).with(user.id, year: nil).once

      clear_enqueued_jobs
      payload = { 'user_id' => user.id, 'point_ids' => [Point.order(:id).first.id], 'force' => true,
                  'event_id' => source.job_id }
      inline = ActiveSupport::IsolatedExecutionState[:job_commands_inline]
      begin
        ActiveSupport::IsolatedExecutionState[:job_commands_inline] = true
        RailsCommands::Registry.handler('geocoding.reverse_point').call(payload)
        expect(enqueued_jobs.map { _1[:job] }).to eq([ReverseGeocodingJob])
        expect(ActiveJob::Arguments.deserialize(enqueued_jobs.first[:args])).to eq(
          ['Point', payload['point_ids'].first, { force: true }]
        )
        clear_enqueued_jobs
        job_owner!('command:geocoding.reverse_point', :oban)
        RailsCommands::Registry.handler('geocoding.reverse_point').call(payload)
        expect(enqueued_jobs).to be_empty
        expect(JobOutbox.find(source.job_id).payload).to eq(payload.except('event_id'))
      ensure
        ActiveSupport::IsolatedExecutionState[:job_commands_inline] = inline
      end
    end

    describe 'queue configuration' do
      it 'uses the reverse_geocoding queue' do
        expect(described_class.queue_name).to eq('reverse_geocoding')
      end
    end

    describe 'error handling' do
      before { configure_instance_geocoding }

      let!(:point_without_geocoding) do
        create(:point, user: user, reverse_geocoded_at: nil)
      end

      context 'when a point fails to reverse geocode' do
        before do
          allow(Geocoding::ReverseCommands).to receive(:enqueue_points).and_raise(StandardError, 'API error')
        end

        it 'propagates the failure instead of silently dropping the batch' do
          expect { described_class.perform_now }.to raise_error(StandardError, 'API error')
        end
      end
    end

    context 'when the environment pins a provider' do
      before do
        ENV['PHOTON_API_HOST'] = 'photon.pinned.example.com'
        InstanceSettings::Resolver.reset!
      end

      it 'enqueues geocoding for the points of every user' do
        other_user = create(:user)
        point = create(:point, user: user, reverse_geocoded_at: nil)
        other_point = create(:point, user: other_user, reverse_geocoded_at: nil)

        described_class.perform_now

        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', point.id, force: false)
        expect(ReverseGeocodingJob).to have_been_enqueued.with('Point', other_point.id, force: false)
      end
    end

    context 'when only a per-user geocoding setting exists' do
      it 'does not enqueue geocoding' do
        create(:service_setting, :active, user: user)
        create(:point, user: user, reverse_geocoded_at: nil)

        expect { described_class.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
      end
    end
  end
end
