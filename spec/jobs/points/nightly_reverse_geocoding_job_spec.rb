# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::NightlyReverseGeocodingJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    before do
      # Clear any existing jobs and points to ensure test isolation
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      Point.delete_all
    end

    context 'when reverse geocoding is disabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      end

      let!(:point_without_geocoding) do
        create(:point, user: user, reverse_geocoded_at: nil)
      end

      it 'does not process any points' do
        expect_any_instance_of(Point).not_to receive(:async_reverse_geocode)

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

    context 'when reverse geocoding is enabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      end

      context 'with no points needing reverse geocoding' do
        let!(:geocoded_point) do
          create(:point, user: user, reverse_geocoded_at: 1.day.ago)
        end

        it 'does not process any points' do
          expect_any_instance_of(Point).not_to receive(:async_reverse_geocode)

          described_class.perform_now
        end

        it 'does not enqueue any ReverseGeocodingJob jobs' do
          expect { described_class.perform_now }.not_to have_enqueued_job(ReverseGeocodingJob)
        end
      end

      context 'with points needing reverse geocoding' do
        let!(:point_without_geocoding1) do
          create(:point, user: user, reverse_geocoded_at: nil)
        end
        let!(:point_without_geocoding2) do
          create(:point, user: user, reverse_geocoded_at: nil)
        end
        let!(:geocoded_point) do
          create(:point, user: user, reverse_geocoded_at: 1.day.ago)
        end

        it 'processes all points that need reverse geocoding' do
          expect { described_class.perform_now }.to have_enqueued_job(ReverseGeocodingJob).exactly(2).times
        end

        it 'enqueues jobs with correct parameters' do
          expect { described_class.perform_now }
            .to have_enqueued_job(ReverseGeocodingJob)
            .with('Point', point_without_geocoding1.id)
            .and have_enqueued_job(ReverseGeocodingJob)
            .with('Point', point_without_geocoding2.id)
        end

        it 'uses find_each with correct batch size' do
          relation_mock = double('ActiveRecord::Relation')
          allow(Point).to receive(:not_reverse_geocoded).and_return(relation_mock)
          allow(relation_mock).to receive(:find_each).with(batch_size: 1000)

          described_class.perform_now

          expect(relation_mock).to have_received(:find_each).with(batch_size: 1000)
        end
      end
    end

    describe 'queue configuration' do
      it 'uses the reverse_geocoding queue' do
        expect(described_class.queue_name).to eq('reverse_geocoding')
      end
    end

    describe 'error handling' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      end

      let!(:point_without_geocoding) do
        create(:point, user: user, reverse_geocoded_at: nil)
      end

      context 'when a point fails to reverse geocode' do
        before do
          allow_any_instance_of(Point).to receive(:async_reverse_geocode).and_raise(StandardError, 'API error')
        end

        it 'continues processing other points despite individual failures' do
          expect { described_class.perform_now }.to raise_error(StandardError, 'API error')
        end
      end
    end
  end
end
