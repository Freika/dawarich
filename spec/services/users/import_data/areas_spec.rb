# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Areas, type: :service do
  let(:user) { create(:user) }
  let(:areas_data) do
    [
      {
        'name' => 'Home',
        'latitude' => '40.7128',
        'longitude' => '-74.0060',
        'radius' => 100,
        'created_at' => '2024-01-01T00:00:00Z',
        'updated_at' => '2024-01-01T00:00:00Z'
      },
      {
        'name' => 'Work',
        'latitude' => '40.7589',
        'longitude' => '-73.9851',
        'radius' => 50,
        'created_at' => '2024-01-02T00:00:00Z',
        'updated_at' => '2024-01-02T00:00:00Z'
      }
    ]
  end
  let(:service) { described_class.new(user, areas_data) }

  describe '#call' do
    context 'with valid areas data' do
      it 'creates new areas for the user' do
        expect { service.call }.to change { user.areas.count }.by(2)
      end

      it 'creates areas with correct attributes' do
        service.call

        home_area = user.areas.find_by(name: 'Home')
        expect(home_area).to have_attributes(
          name: 'Home',
          latitude: 40.7128,
          longitude: -74.0060,
          radius: 100
        )

        work_area = user.areas.find_by(name: 'Work')
        expect(work_area).to have_attributes(
          name: 'Work',
          latitude: 40.7589,
          longitude: -73.9851,
          radius: 50
        )
      end

      it 'returns the number of areas created' do
        result = service.call
        expect(result).to eq(2)
      end

      it 'logs the import process' do
        expect(Rails.logger).to receive(:info).with("Importing 2 areas for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Areas import completed. Created: 2")

        service.call
      end
    end

    context 'with duplicate areas' do
      before do
        # Create an existing area with same name and coordinates
        user.areas.create!(
          name: 'Home',
          latitude: 40.7128,
          longitude: -74.0060,
          radius: 100
        )
      end

      it 'skips duplicate areas' do
        expect { service.call }.to change { user.areas.count }.by(1)
      end

      it 'logs when skipping duplicates' do
        allow(Rails.logger).to receive(:debug) # Allow any debug logs
        expect(Rails.logger).to receive(:debug).with("Area already exists: Home")

        service.call
      end

      it 'returns only the count of newly created areas' do
        result = service.call
        expect(result).to eq(1)
      end
    end

    context 'with invalid area data' do
      let(:areas_data) do
        [
          { 'name' => 'Valid Area', 'latitude' => '40.7128', 'longitude' => '-74.0060', 'radius' => 100 },
          'invalid_data',
          { 'name' => 'Another Valid Area', 'latitude' => '40.7589', 'longitude' => '-73.9851', 'radius' => 50 }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        expect { service.call }.to change { user.areas.count }.by(2)
      end

      it 'returns the count of valid areas created' do
        result = service.call
        expect(result).to eq(2)
      end
    end

    context 'with nil areas data' do
      let(:areas_data) { nil }

      it 'does not create any areas' do
        expect { service.call }.not_to change { user.areas.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with non-array areas data' do
      let(:areas_data) { 'invalid_data' }

      it 'does not create any areas' do
        expect { service.call }.not_to change { user.areas.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with empty areas data' do
      let(:areas_data) { [] }

      it 'does not create any areas' do
        expect { service.call }.not_to change { user.areas.count }
      end

      it 'logs the import process with 0 count' do
        expect(Rails.logger).to receive(:info).with("Importing 0 areas for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Areas import completed. Created: 0")

        service.call
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end
end
