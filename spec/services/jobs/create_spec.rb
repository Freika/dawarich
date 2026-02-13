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
  end
end
