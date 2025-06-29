# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ImportData::Stats, type: :service do
  let(:user) { create(:user) }
  let(:stats_data) do
    [
      {
        'year' => 2024,
        'month' => 1,
        'distance' => 456.78,
        'daily_distance' => [[1, 15.2], [2, 23.5], [3, 18.1]],
        'toponyms' => [
          { 'country' => 'United States', 'cities' => [{ 'city' => 'New York' }] }
        ],
        'created_at' => '2024-02-01T00:00:00Z',
        'updated_at' => '2024-02-01T00:00:00Z'
      },
      {
        'year' => 2024,
        'month' => 2,
        'distance' => 321.45,
        'daily_distance' => [[1, 12.3], [2, 19.8], [3, 25.4]],
        'toponyms' => [
          { 'country' => 'Canada', 'cities' => [{ 'city' => 'Toronto' }] }
        ],
        'created_at' => '2024-03-01T00:00:00Z',
        'updated_at' => '2024-03-01T00:00:00Z'
      }
    ]
  end
  let(:service) { described_class.new(user, stats_data) }

  describe '#call' do
    context 'with valid stats data' do
      it 'creates new stats for the user' do
        expect { service.call }.to change { user.stats.count }.by(2)
      end

      it 'creates stats with correct attributes' do
        service.call

        jan_stats = user.stats.find_by(year: 2024, month: 1)
        expect(jan_stats).to have_attributes(
          year: 2024,
          month: 1,
          distance: 456
        )
        expect(jan_stats.daily_distance).to eq([[1, 15.2], [2, 23.5], [3, 18.1]])
        expect(jan_stats.toponyms).to eq([{ 'country' => 'United States', 'cities' => [{ 'city' => 'New York' }] }])

        feb_stats = user.stats.find_by(year: 2024, month: 2)
        expect(feb_stats).to have_attributes(
          year: 2024,
          month: 2,
          distance: 321
        )
        expect(feb_stats.daily_distance).to eq([[1, 12.3], [2, 19.8], [3, 25.4]])
        expect(feb_stats.toponyms).to eq([{ 'country' => 'Canada', 'cities' => [{ 'city' => 'Toronto' }] }])
      end

      it 'returns the number of stats created' do
        result = service.call
        expect(result).to eq(2)
      end

      it 'logs the import process' do
        expect(Rails.logger).to receive(:info).with("Importing 2 stats for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Stats import completed. Created: 2")

        service.call
      end
    end

    context 'with duplicate stats (same year and month)' do
      before do
        # Create an existing stat with same year and month
        user.stats.create!(
          year: 2024,
          month: 1,
          distance: 100.0
        )
      end

      it 'skips duplicate stats' do
        expect { service.call }.to change { user.stats.count }.by(1)
      end

      it 'logs when skipping duplicates' do
        allow(Rails.logger).to receive(:debug) # Allow any debug logs
        expect(Rails.logger).to receive(:debug).with("Stat already exists: 2024-1")

        service.call
      end

      it 'returns only the count of newly created stats' do
        result = service.call
        expect(result).to eq(1)
      end
    end

    context 'with invalid stat data' do
      let(:stats_data) do
        [
          { 'year' => 2024, 'month' => 1, 'distance' => 456.78 },
          'invalid_data',
          { 'year' => 2024, 'month' => 2, 'distance' => 321.45 }
        ]
      end

      it 'skips invalid entries and imports valid ones' do
        expect { service.call }.to change { user.stats.count }.by(2)
      end

      it 'returns the count of valid stats created' do
        result = service.call
        expect(result).to eq(2)
      end
    end

    context 'with validation errors' do
      let(:stats_data) do
        [
          { 'year' => 2024, 'month' => 1, 'distance' => 456.78 },
          { 'month' => 1, 'distance' => 321.45 }, # missing year
          { 'year' => 2024, 'distance' => 123.45 } # missing month
        ]
      end

      it 'only creates valid stats' do
        expect { service.call }.to change { user.stats.count }.by(1)
      end

      it 'logs validation errors' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        service.call
      end
    end

    context 'with nil stats data' do
      let(:stats_data) { nil }

      it 'does not create any stats' do
        expect { service.call }.not_to change { user.stats.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with non-array stats data' do
      let(:stats_data) { 'invalid_data' }

      it 'does not create any stats' do
        expect { service.call }.not_to change { user.stats.count }
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end

    context 'with empty stats data' do
      let(:stats_data) { [] }

      it 'does not create any stats' do
        expect { service.call }.not_to change { user.stats.count }
      end

      it 'logs the import process with 0 count' do
        expect(Rails.logger).to receive(:info).with("Importing 0 stats for user: #{user.email}")
        expect(Rails.logger).to receive(:info).with("Stats import completed. Created: 0")

        service.call
      end

      it 'returns 0' do
        result = service.call
        expect(result).to eq(0)
      end
    end
  end
end
