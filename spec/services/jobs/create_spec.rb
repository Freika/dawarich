# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::Create do
  describe '#call' do
    before do
      allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
      clear_geocode_claims!
    end

    context 'when job_name is start_reverse_geocoding' do
      before { configure_instance_geocoding }

      let(:user) { create(:user) }
      let(:points) do
        (1..4).map do |i|
          create(:point, user:, timestamp: 1.day.ago + i.minutes)
        end
      end

      let(:job_name) { 'start_reverse_geocoding' }

      it 'enqueues reverse geocoding for all user points' do
        created_points = points # force creation before the service call
        clear_geocode_claims!

        expect do
          described_class.new(job_name, user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).exactly(created_points.size).times
      end
    end

    context 'when job_name is continue_reverse_geocoding' do
      before { configure_instance_geocoding }

      let(:user) { create(:user) }
      let(:points_without_address) do
        (1..4).map do |i|
          create(:point, user:, country: nil, city: nil, timestamp: 1.day.ago + i.minutes)
        end
      end

      let(:points_with_address) do
        (1..5).map do |i|
          create(:point, user:, country: 'Country', city: 'City',
                         reverse_geocoded_at: Time.current, timestamp: 1.day.ago + i.minutes)
        end
      end

      let(:job_name) { 'continue_reverse_geocoding' }

      it 'enqueues reverse geocoding for all user points without address' do
        _with_address = points_with_address # force creation
        without_address = points_without_address # force creation
        clear_geocode_claims!

        expect do
          described_class.new(job_name, user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).exactly(without_address.size).times
      end
    end

    context 'when geocoding is not configured for the instance' do
      let(:user) { create(:user) }

      it 'enqueues nothing for a user without settings' do
        create(:point, user: user)

        expect do
          described_class.new('start_reverse_geocoding', user.id).call
        end.not_to have_enqueued_job(ReverseGeocodingJob)
      end

      it 'enqueues nothing even when the user has an active geocoding setting' do
        create(:service_setting, :geoapify, :active, user: user)
        create(:point, user: user)

        expect do
          described_class.new('start_reverse_geocoding', user.id).call
        end.not_to have_enqueued_job(ReverseGeocodingJob)
      end
    end

    context 'when job_name is invalid' do
      let(:user) { create(:user) }
      let(:job_name) { 'invalid_job_name' }

      it 'raises an error' do
        expect { described_class.new(job_name, user.id).call }.to raise_error(Jobs::Create::InvalidJobName)
      end
    end

    context 'when forcing rerun on a paid provider on a hosted (non-self-hosted) instance' do
      let(:user) { create(:user) }

      before do
        configure_instance_geocoding(locationiq_api_key: 'test-api-key')
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'raises PaidProviderForceRerunBlocked and enqueues no jobs' do
        create(:point, user:, timestamp: 1.day.ago)

        expect do
          expect do
            described_class.new('start_reverse_geocoding', user.id).call
          end.to raise_error(Jobs::Create::PaidProviderForceRerunBlocked)
        end.not_to have_enqueued_job(ReverseGeocodingJob)
      end
    end

    context 'when forcing rerun on a paid provider on a self-hosted instance' do
      let(:user) { create(:user) }

      before do
        configure_instance_geocoding(locationiq_api_key: 'test-api-key')
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it 'enqueues jobs because the operator owns their own provider bill' do
        create(:point, user:, timestamp: 1.day.ago)

        expect do
          described_class.new('start_reverse_geocoding', user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).at_least(:once)
      end
    end

    context 'when continue_reverse_geocoding runs on a paid provider' do
      let(:user) { create(:user) }

      before do
        configure_instance_geocoding(locationiq_api_key: 'test-api-key')
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'is not blocked because force is false' do
        create(:point, user:, country: nil, city: nil, timestamp: 1.day.ago)
        clear_geocode_claims!

        expect do
          described_class.new('continue_reverse_geocoding', user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).at_least(:once)
      end
    end

    context 'dedup interaction' do
      let(:user) { create(:user) }
      let!(:point) { create(:point, user:, country: nil, city: nil, reverse_geocoded_at: nil) }

      before do
        configure_instance_geocoding
        clear_geocode_claims!
      end

      it 'skips continue_reverse_geocoding when a dedup key already claims the point' do
        PhoenixClaims.claim(Point.geocode_dedup_key(point.id), Point::GEOCODE_DEDUP_TTL)

        expect do
          described_class.new('continue_reverse_geocoding', user.id).call
        end.not_to have_enqueued_job(ReverseGeocodingJob)
      end

      it 'claims the dedup key for points enqueued via continue_reverse_geocoding' do
        described_class.new('continue_reverse_geocoding', user.id).call

        expect(claim_seconds(Point.geocode_dedup_key(point.id))).to be_between(86_399, 86_400)
      end

      it 'clears the dedup key when start_reverse_geocoding force-runs over an existing claim' do
        PhoenixClaims.claim(Point.geocode_dedup_key(point.id), Point::GEOCODE_DEDUP_TTL)

        expect do
          described_class.new('start_reverse_geocoding', user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).with('Point', point.id, force: true)
      end

      it 'releases dedup keys when bulk enqueue raises after claiming' do
        allow(ActiveJob).to receive(:perform_all_later).and_raise(StandardError, 'queue down')

        expect do
          described_class.new('continue_reverse_geocoding', user.id).call
        end.to raise_error(StandardError, 'queue down')

        expect(claim_seconds(Point.geocode_dedup_key(point.id))).to be_nil
      end

      it 'Oban-owned continue_reverse_geocoding writes a batch instead of enqueueing' do
        job_owner!('command:geocoding.reverse_point', :oban)

        expect do
          described_class.new('continue_reverse_geocoding', user.id).call
        end.not_to have_enqueued_job(ReverseGeocodingJob)

        row = JobOutbox.sole
        expect(row).to have_attributes(command_type: 'geocoding.reverse_point', aggregate_id: user.id)
        expect(row.payload).to eq('user_id' => user.id, 'point_ids' => [point.id], 'force' => false)
      end
    end
  end
end
