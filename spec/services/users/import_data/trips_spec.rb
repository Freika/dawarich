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

  describe '#call' do
    context 'with trips exported from TREK' do
      before do
        allow(Resolv).to receive(:getaddress).with('trek.example.test').and_return('93.184.216.34')
      end

      let(:original_user) { create(:user) }
      let(:source) { create(:trip_source, user: original_user) }
      let(:snapshot) do
        {
          'title' => 'Tuscany', 'start_date' => '2030-06-14', 'end_date' => '2030-06-15',
          'days' => [{
            'date' => '2030-06-14', 'day_number' => 1, 'notes' => 'Arrival',
            'places' => [{ 'name' => 'Museum', 'lat' => 43.76, 'lng' => 11.25 }],
            'day_notes' => [{ 'text' => 'Bring tickets', 'time' => '09:00' }],
            'reservations' => [{ 'title' => 'Dinner', 'time' => '19:00' }]
          }],
          'unscheduled_reservations' => [{ 'title' => 'Train' }],
          'accommodations' => [{ 'name' => 'Hotel' }],
          'travellers' => [{ 'name' => 'Ada', 'owner' => true }],
          'unplanned_places' => [{ 'name' => 'Market' }]
        }
      end
      let!(:original_trip) do
        create(:trip, user: original_user, trip_source: source, source_identifier: '12', source_status: :active,
                      started_at: '2030-06-14', ended_at: '2030-06-15', source_snapshot: snapshot)
      end

      it 'restores a stopped, detached trip and all visible itinerary records from an exported snapshot' do
        exported = Users::ExportData::Trips.new(original_user).call

        expect(described_class.new(user, exported).call).to eq(1)

        restored = user.trips.last
        expect(restored).to have_attributes(trip_source_id: nil, source_status: 'stopped', source_snapshot: snapshot)
        day = restored.planned_days.sole
        expect(day.notes).to eq('Arrival')
        expect(day.planned_stops.sole.name).to eq('Museum')
        expect(day.planned_day_notes.sole.body).to eq('Bring tickets')
        expect(day.planned_reservations.sole.title).to eq('Dinner')
        expect(restored.planned_reservations.where(planned_day_id: nil).sole.title).to eq('Train')
        expect(restored.planned_accommodations.sole.name).to eq('Hotel')
        expect(restored.planned_travellers.sole.name).to eq('Ada')
        expect(restored.planned_unplanned_places.sole.name).to eq('Market')
        expect(source.trips.pluck(:id)).to eq([original_trip.id])
      end

      it 'ignores source and record IDs in an older backup when the source belongs to another user' do
        exported = original_trip.as_json.merge('id' => original_trip.id, 'trip_source_id' => source.id)

        expect(described_class.new(user, [exported]).call).to eq(1)

        restored = user.trips.sole
        expect(restored.id).not_to eq(original_trip.id)
        expect(restored.trip_source).to be_nil
        expect(restored).to be_source_stopped
        expect(original_trip.reload.user_id).to eq(original_user.id)
      end

      it 'restores ordinary trips alongside an older backup whose source no longer exists' do
        exported = original_trip.as_json(except: %w[id user_id])
        original_trip.destroy!
        source.destroy!

        expect(described_class.new(user, trips_data + [exported]).call).to eq(3)
        expect(user.trips.count).to eq(3)
        expect(user.trips.where.not(trip_source_id: nil)).to be_empty
      end

      it 'keeps other trips when an itinerary snapshot is invalid' do
        exported = original_trip.as_json(except: %w[id user_id]).merge('source_snapshot' => { 'days' => [{}] })

        expect(described_class.new(user, trips_data + [exported]).call).to eq(2)
        expect(user.trips.count).to eq(2)
        expect(user.trips.find_by(source_identifier: '12')).to be_nil
      end
    end

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
        expect(Rails.logger).to receive(:info).with('Trips import completed. Created: 2')

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
        expect(Rails.logger).to receive(:debug).with('Trip already exists: Business Trip to NYC')

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
          { 'name' => 'Another Valid Trip', 'started_at' => '2024-02-10T09:00:00Z',
'ended_at' => '2024-02-12T18:00:00Z' }
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
        expect { service.call }.not_to(change { user.trips.count })
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with non-array trips data' do
      let(:trips_data) { 'invalid_data' }

      it 'does not create any trips' do
        expect { service.call }.not_to(change { user.trips.count })
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with empty trips data' do
      let(:trips_data) { [] }

      it 'does not create any trips' do
        expect { service.call }.not_to(change { user.trips.count })
      end

      it 'logs the import process with 0 count' do
        expect(Rails.logger).to receive(:info).with("Importing 0 trips for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with('Trips import completed. Created: 0')

        service.call
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end
end
