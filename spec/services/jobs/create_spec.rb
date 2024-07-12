# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::Create do
  describe '#call' do
    context 'when job_name is start_reverse_geocoding' do
      let(:user) { create(:user) }
      let(:points) { create_list(:point, 4, user:) }
      let(:job_name) { 'start_reverse_geocoding' }

      it 'enqueues reverse geocoding for all user points' do
        allow(ReverseGeocodingJob).to receive(:perform_later).and_return(nil)

        described_class.new(job_name, user.id).call

        points.each do |point|
          expect(ReverseGeocodingJob).to have_received(:perform_later).with(point.id)
        end
      end
    end

    context 'when job_name is continue_reverse_geocoding' do
      let(:user) { create(:user) }
      let(:points_without_address) { create_list(:point, 4, user:, country: nil, city: nil) }
      let(:points_with_address) { create_list(:point, 5, user:, country: 'Country', city: 'City') }

      let(:job_name) { 'continue_reverse_geocoding' }

      it 'enqueues reverse geocoding for all user points without address' do
        allow(ReverseGeocodingJob).to receive(:perform_later).and_return(nil)

        described_class.new(job_name, user.id).call

        points_without_address.each do |point|
          expect(ReverseGeocodingJob).to have_received(:perform_later).with(point.id)
        end
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
