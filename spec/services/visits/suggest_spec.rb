# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Suggest do
  describe '#call' do
    let!(:user) { create(:user) }
    let(:start_at) { Time.zone.local(2020, 1, 1, 0, 0, 0) }
    let(:end_at) { Time.zone.local(2020, 1, 1, 5, 0, 0) }

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

    it 'creates separate visits across a same-location time gap above the configured maximum' do
      expect { subject }.to change(Visit, :count).by(2)
    end

    it 'creates visits notification' do
      expect { subject }.to change(Notification, :count).by(1)
    end

    context 'when reverse geocoding is enabled' do
      let(:reverse_geocoding_start_at) { Time.zone.local(2020, 6, 1, 0, 0, 0) }
      let(:reverse_geocoding_end_at) { Time.zone.local(2020, 6, 1, 5, 0, 0) }

      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)

        create_visit_points(user, reverse_geocoding_start_at)
        clear_enqueued_jobs
      end

      it 'enqueues reverse geocoding jobs for created visits' do
        described_class.new(user, start_at: reverse_geocoding_start_at, end_at: reverse_geocoding_end_at).call

        # Since both visits are at the same location, they share the same place.
        # So only 1 ReverseGeocodingJob should be enqueued. (Places::NameFetchingJob
        # is also enqueued by PlaceFinder when reverse geocoding is enabled, but
        # that's a separate concern and not what this test is asserting.)
        reverse_geocoding_jobs = enqueued_jobs.select { |job| job['job_class'] == 'ReverseGeocodingJob' }
        expect(reverse_geocoding_jobs.count).to eq(1)
        expect(reverse_geocoding_jobs).to all(have_arguments_starting_with('place'))
      end
    end

    context 'when reverse geocoding is disabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
        clear_enqueued_jobs
      end

      it 'does not reverse geocode visits' do
        subject
        expect(enqueued_jobs).to be_empty
      end
    end

    context 'when detection raises' do
      before do
        allow(Visits::SmartDetect).to receive(:new).and_raise(StandardError, 'detector exploded')
        Sidekiq.redis { |redis| redis.del("visit_suggest_error:user:#{user.id}") }
      end

      after do
        Sidekiq.redis { |redis| redis.del("visit_suggest_error:user:#{user.id}") }
      rescue StandardError
        nil
      end

      it 'returns an empty collection' do
        expect(described_class.new(user, start_at:, end_at:).call).to eq([])
      end

      it 'logs the failure with a backtrace for self-hosted operators' do
        allow(Rails.logger).to receive(:error)

        described_class.new(user, start_at:, end_at:).call

        expect(Rails.logger).to have_received(:error).with(/detector exploded/)
      end

      it 'does not repeat the notification while an unread one is recent' do
        3.times { described_class.new(user, start_at:, end_at:).call }

        expect(user.notifications.where(title: 'Error suggesting visits').count).to eq(1)
      end

      it 'notifies again once the dedup window has passed' do
        described_class.new(user, start_at:, end_at:).call
        Sidekiq.redis { |redis| redis.del("visit_suggest_error:user:#{user.id}") }

        described_class.new(user, start_at:, end_at:).call

        expect(user.notifications.where(title: 'Error suggesting visits').count).to eq(2)
      end

      it 'suppresses the notification when another run already claimed the window' do
        Sidekiq.redis { |redis| redis.set("visit_suggest_error:user:#{user.id}", 1, ex: 3600) }

        described_class.new(user, start_at:, end_at:).call

        expect(user.notifications.where(title: 'Error suggesting visits')).to be_empty
      end

      it 'still notifies when Redis is unavailable' do
        allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError, 'redis down')

        described_class.new(user, start_at:, end_at:).call

        expect(user.notifications.where(title: 'Error suggesting visits').count).to eq(1)
      end

      it 'notifies the user without leaking a backtrace' do
        described_class.new(user, start_at:, end_at:).call

        notification = user.notifications.order(:id).last

        expect(notification.kind).to eq('error')
        expect(notification.content).to include('detector exploded')
        expect(notification.content).not_to match(/\.rb:\d+/)
      end
    end

    # The Lite plan window is enforced inside `Visits::SmartDetect` (which is
    # what `Visits::Suggest#call` delegates to). The corresponding regression
    # test lives in spec/services/visits/smart_detect_spec.rb.
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
      create(:point, :with_known_location, user:, timestamp: start_time + 180.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 185.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 190.minutes)
      # end of second visit
    ]
  end

  def have_job_class(job_class)
    satisfy { |job| job['job_class'] == job_class }
  end

  def have_arguments_starting_with(first_argument)
    satisfy { |job| job['arguments'].first == first_argument }
  end
end
