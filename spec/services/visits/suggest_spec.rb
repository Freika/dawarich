# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Suggest do
  describe '#call' do
    let!(:user) { create(:user) }
    let(:start_at) { Time.zone.local(2020, 1, 1, 0, 0, 0) }
    let(:end_at) { Time.zone.local(2020, 1, 1, 2, 0, 0) }

    let!(:points) do
      [
        # first visit
        create(:point, :with_known_location, user:, timestamp: start_at),
        create(:point, :with_known_location, user:, timestamp: start_at + 5.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 10.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 15.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 20.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 25.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 30.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 35.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 40.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 45.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 50.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 55.minutes),
        # end of first visit

        # second visit
        create(:point, :with_known_location, user:, timestamp: start_at + 95.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 100.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 105.minutes)
        # end of second visit
      ]
    end

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
      expect { subject }.to change(Visit, :count).by(2)
    end

    it 'creates visits notification' do
      expect { subject }.to change(Notification, :count).by(1)
    end

    context 'when reverse geocoding is enabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      end

      it 'reverse geocodes visits' do
        expect { subject }.to have_enqueued_job(ReverseGeocodingJob).exactly(2).times
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
end
