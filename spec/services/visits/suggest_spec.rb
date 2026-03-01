# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Suggest do
  describe '#call' do
    let!(:user) { create(:user) }
    let(:start_at) { Time.zone.local(2020, 1, 1, 0, 0, 0) }
    let(:end_at) { Time.zone.local(2020, 1, 1, 2, 0, 0) }

    let!(:points) { create_visit_points(user, start_at) }

    let(:geocoder_struct) do
      Struct.new(:data) do
        def data
          {
            "features": [
              {
                "geometry": {
                  "coordinates": [
                    37.6175406,
                    55.7559395
                  ],
                  "type": 'Point'
                },
                "type": 'Feature',
                "properties": {
                  "osm_id": 681_354_082,
                  "extent": [
                    37.6175406,
                    55.7559395,
                    37.6177036,
                    55.755847
                  ],
                  "country": 'Russia',
                  "city": 'Moscow',
                  "countrycode": 'RU',
                  "postcode": '103265',
                  "type": 'street',
                  "osm_type": 'W',
                  "osm_key": 'highway',
                  "district": 'Tverskoy',
                  "osm_value": 'pedestrian',
                  "name": 'проезд Воскресенские Ворота',
                  "state": 'Moscow'
                }
              }
            ],
            "type": 'FeatureCollection'
          }
        end
      end
    end

    let(:geocoder_response) do
      [geocoder_struct.new]
    end

    subject { described_class.new(user, start_at:, end_at:).call }

    before do
      allow(Geocoder).to receive(:search).and_return(geocoder_response)
    end

    it 'creates places' do
      expect { subject }.to change(Place, :count).by(1)
    end

    it 'creates visits' do
      # With density normalization enabled (default), the 40-minute gap between
      # two point groups at the same location is bridged, producing 1 visit.
      expect { subject }.to change(Visit, :count).by(1)
    end

    it 'creates visits notification' do
      expect { subject }.to change(Notification, :count).by(1)
    end

    context 'when reverse geocoding is enabled' do
      let(:reverse_geocoding_start_at) { Time.zone.local(2020, 6, 1, 0, 0, 0) }
      let(:reverse_geocoding_end_at) { Time.zone.local(2020, 6, 1, 2, 0, 0) }

      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)

        create_visit_points(user, reverse_geocoding_start_at)
        clear_enqueued_jobs
      end

      it 'enqueues reverse geocoding jobs for created visits' do
        described_class.new(user, start_at: reverse_geocoding_start_at, end_at: reverse_geocoding_end_at).call

        # 1 visit (density normalization bridges the gap) → 1 reverse geocoding job
        expect(enqueued_jobs.count).to eq(1)
        expect(enqueued_jobs).to all(have_job_class('ReverseGeocodingJob'))
        expect(enqueued_jobs).to all(have_arguments_starting_with('place'))
      end
    end

    context 'when reverse geocoding is disabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      end

      it 'does not reverse geocode visits' do
        expect_any_instance_of(Visit).not_to receive(:async_reverse_geocode)
        subject
      end
    end
  end

  private

  def create_visit_points(user, start_time)
    [
      # first visit
      create(:point, :with_known_location, user:, timestamp: start_time),
      create(:point, :with_known_location, user:, timestamp: start_time + 5.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 10.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 15.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 20.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 25.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 30.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 35.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 40.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 45.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 50.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 55.minutes),
      # end of first visit

      # second visit
      create(:point, :with_known_location, user:, timestamp: start_time + 95.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 100.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 105.minutes)
      # end of second visit
    ]
  end

  def clear_enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def have_job_class(job_class)
    satisfy { |job| job['job_class'] == job_class }
  end

  def have_arguments_starting_with(first_argument)
    satisfy { |job| job['arguments'].first == first_argument }
  end
end
