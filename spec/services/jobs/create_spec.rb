# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::Create do
  describe '#call' do
    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
    end

    context 'when job_name is start_reverse_geocoding' do
      let(:user) { create(:user) }
      let(:points) do
        (1..4).map do |i|
          create(:point, user:, timestamp: 1.day.ago + i.minutes)
        end
      end

      let(:job_name) { 'start_reverse_geocoding' }

      it 'enqueues reverse geocoding for all user points' do
        created_points = points # force creation before the service call

        expect do
          described_class.new(job_name, user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).exactly(created_points.size).times
      end
    end

    context 'when job_name is continue_reverse_geocoding' do
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

        expect do
          described_class.new(job_name, user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).exactly(without_address.size).times
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
        allow(DawarichSettings).to receive(:locationiq_enabled?).and_return(true)
        allow(DawarichSettings).to receive(:geoapify_enabled?).and_return(false)
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
        allow(DawarichSettings).to receive(:locationiq_enabled?).and_return(true)
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
        allow(DawarichSettings).to receive(:locationiq_enabled?).and_return(true)
      end

      it 'is not blocked because force is false' do
        create(:point, user:, country: nil, city: nil, timestamp: 1.day.ago)

        expect do
          described_class.new('continue_reverse_geocoding', user.id).call
        end.to have_enqueued_job(ReverseGeocodingJob).at_least(:once)
      end
    end
  end
end
