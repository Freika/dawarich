# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Trips, type: :service do
  let(:user) { create(:user) }
  let(:trips_data) do
    [
      {
        'name' => 'Business Trip to NYC',
        'started_at' => '2024-01-15T08:00:00Z',
        'ended_at' => '2024-01-18T20:00:00Z',
        'distance' => 1245.67,
        'created_at' => '2024-01-19T00:00:00Z',
        'updated_at' => '2024-01-19T00:00:00Z'
      },
      {
        'name' => 'Weekend Getaway',
        'started_at' => '2024-02-10T09:00:00Z',
        'ended_at' => '2024-02-12T18:00:00Z',
        'distance' => 456.78,
        'created_at' => '2024-02-13T00:00:00Z',
        'updated_at' => '2024-02-13T00:00:00Z'
      }
    ]
  end
  let(:service) { described_class.new(user, trips_data) }

  before do
    # Mock the job enqueuing to avoid it interfering with tests
    allow(Trips::CalculateAllJob).to receive(:perform_later)
  end

  describe '#call' do
    context 'with valid trips data' do
      it 'creates new trips for the user' do
        expect { service.call }.to change { user.trips.count }.by(2)
      end

      it 'creates trips with correct attributes' do
        service.call

        business_trip = user.trips.find_by(name: 'Business Trip to NYC')
        expect(business_trip).to have_attributes(
          name: 'Business Trip to NYC',
          started_at: Time.parse('2024-01-15T08:00:00Z'),
          ended_at: Time.parse('2024-01-18T20:00:00Z'),
          distance: 1245
        )

        weekend_trip = user.trips.find_by(name: 'Weekend Getaway')
        expect(weekend_trip).to have_attributes(
          name: 'Weekend Getaway',
          started_at: Time.parse('2024-02-10T09:00:00Z'),
          ended_at: Time.parse('2024-02-12T18:00:00Z'),
          distance: 456
        )
      end

      it 'returns the number of trips created' do
        result = service.call
        expect(result).to eq(2)
      end

      it 'logs the import process' do
        expect(Rails.logger).to receive(:info).with("Importing 2 trips for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Trips import completed. Created: 2")

        service.call
      end
    end

    context 'with duplicate trips' do
      before do
        # Create an existing trip with same name and times
        user.trips.create!(
          name: 'Business Trip to NYC',
          started_at: Time.parse('2024-01-15T08:00:00Z'),
          ended_at: Time.parse('2024-01-18T20:00:00Z'),
          distance: 1000.0
        )
      end

      it 'skips duplicate trips' do
        expect { service.call }.to change { user.trips.count }.by(1)
      end

      it 'logs when skipping duplicates' do
        allow(Rails.logger).to receive(:debug) # Allow any debug logs
        expect(Rails.logger).to receive(:debug).with("Trip already exists: Business Trip to NYC")

        service.call
      end

      it 'returns only the count of newly created trips' do
        result = service.call
        expect(result).to eq(1)
      end
    end

    context 'with invalid trip data' do
      let(:trips_data) do
        [
          { 'name' => 'Valid Trip', 'started_at' => '2024-01-15T08:00:00Z', 'ended_at' => '2024-01-18T20:00:00Z' },
          'invalid_data',
          { 'name' => 'Another Valid Trip', 'started_at' => '2024-02-10T09:00:00Z', 'ended_at' => '2024-02-12T18:00:00Z' }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        expect { service.call }.to change { user.trips.count }.by(2)
      end

      it 'returns the count of valid trips created' do
        result = service.call
        expect(result).to eq(2)
      end
    end

    context 'with validation errors' do
      let(:trips_data) do
        [
          { 'name' => 'Valid Trip', 'started_at' => '2024-01-15T08:00:00Z', 'ended_at' => '2024-01-18T20:00:00Z' },
          { 'started_at' => '2024-01-15T08:00:00Z', 'ended_at' => '2024-01-18T20:00:00Z' }, # missing name
          { 'name' => 'Invalid Trip' } # missing required timestamps
        ]
      end

      it 'only creates valid trips' do
        expect { service.call }.to change { user.trips.count }.by(1)
      end
    end

    context 'with nil trips data' do
      let(:trips_data) { nil }

      it 'does not create any trips' do
        expect { service.call }.not_to change { user.trips.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with non-array trips data' do
      let(:trips_data) { 'invalid_data' }

      it 'does not create any trips' do
        expect { service.call }.not_to change { user.trips.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with empty trips data' do
      let(:trips_data) { [] }

      it 'does not create any trips' do
        expect { service.call }.not_to change { user.trips.count }
      end

      it 'logs the import process with 0 count' do
        expect(Rails.logger).to receive(:info).with("Importing 0 trips for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Trips import completed. Created: 0")

        service.call
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end
end
