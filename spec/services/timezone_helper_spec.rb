# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimezoneHelper do
  include ActiveSupport::Testing::TimeHelpers

  describe '.month_bounds' do
    context 'with UTC timezone' do
      it 'returns correct timestamps for January 2024' do
        start_ts, end_ts = described_class.month_bounds(2024, 1, 'UTC')

        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 1, 1, 0, 0, 0))
        expect(Time.at(end_ts).utc.to_date).to eq(Date.new(2024, 1, 31))
      end
    end

    context 'with non-UTC timezone' do
      it 'returns correct timestamps for a user in UTC+8 (Singapore)' do
        start_ts, end_ts = described_class.month_bounds(2024, 1, 'Asia/Singapore')

        # January 1st 00:00 in Singapore is December 31st 16:00 UTC
        expect(Time.at(start_ts).utc).to eq(Time.utc(2023, 12, 31, 16, 0, 0))
        # January 31st 23:59:59 in Singapore is January 31st 15:59:59 UTC
        expect(Time.at(end_ts).utc.to_date).to eq(Date.new(2024, 1, 31))
      end

      it 'returns correct timestamps for a user in UTC-5 (New York)' do
        start_ts, _end_ts = described_class.month_bounds(2024, 1, 'America/New_York')

        # January 1st 00:00 in New York is January 1st 05:00 UTC
        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 1, 1, 5, 0, 0))
      end
    end

    context 'with invalid timezone' do
      it 'falls back to UTC' do
        start_ts, _end_ts = described_class.month_bounds(2024, 1, 'Invalid/Timezone')

        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 1, 1, 0, 0, 0))
      end
    end
  end

  describe '.year_bounds' do
    context 'with UTC timezone' do
      it 'returns correct timestamps for 2024' do
        start_ts, end_ts = described_class.year_bounds(2024, 'UTC')

        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 1, 1, 0, 0, 0))
        expect(Time.at(end_ts).utc.to_date).to eq(Date.new(2024, 12, 31))
      end
    end

    context 'with non-UTC timezone' do
      it 'returns correct timestamps for a user in UTC+8 (Singapore)' do
        start_ts, _end_ts = described_class.year_bounds(2024, 'Asia/Singapore')

        # January 1st 00:00 in Singapore is December 31st 16:00 UTC (previous year)
        expect(Time.at(start_ts).utc).to eq(Time.utc(2023, 12, 31, 16, 0, 0))
      end
    end
  end

  describe '.day_bounds' do
    context 'with UTC timezone' do
      it 'returns correct timestamps for a specific date' do
        date = Date.new(2024, 6, 15)
        start_ts, end_ts = described_class.day_bounds(date, 'UTC')

        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 6, 15, 0, 0, 0))
        expect(Time.at(end_ts).utc.to_date).to eq(Date.new(2024, 6, 15))
      end
    end

    context 'with non-UTC timezone' do
      it 'returns correct timestamps for a user in UTC+8 (Singapore)' do
        date = Date.new(2024, 6, 15)
        start_ts, end_ts = described_class.day_bounds(date, 'Asia/Singapore')

        # June 15th 00:00 in Singapore is June 14th 16:00 UTC
        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 6, 14, 16, 0, 0))
        # End of day should still be June 15th in Singapore timezone
        expect(Time.at(end_ts).in_time_zone('Asia/Singapore').to_date).to eq(Date.new(2024, 6, 15))
      end
    end
  end

  describe '.timestamp_to_date' do
    it 'converts timestamp to correct date in UTC' do
      # Timestamp for 2024-06-15 12:00:00 UTC
      timestamp = Time.utc(2024, 6, 15, 12, 0, 0).to_i
      date = described_class.timestamp_to_date(timestamp, 'UTC')

      expect(date).to eq(Date.new(2024, 6, 15))
    end

    it 'converts timestamp to correct date in different timezone' do
      # Timestamp for 2024-06-15 04:00:00 UTC (which is 2024-06-15 12:00:00 in Singapore)
      timestamp = Time.utc(2024, 6, 15, 4, 0, 0).to_i
      date = described_class.timestamp_to_date(timestamp, 'Asia/Singapore')

      expect(date).to eq(Date.new(2024, 6, 15))
    end

    it 'handles day boundary correctly for different timezones' do
      # Timestamp for 2024-06-15 22:00:00 UTC
      # In Singapore (UTC+8), this is 2024-06-16 06:00:00
      timestamp = Time.utc(2024, 6, 15, 22, 0, 0).to_i

      utc_date = described_class.timestamp_to_date(timestamp, 'UTC')
      singapore_date = described_class.timestamp_to_date(timestamp, 'Asia/Singapore')

      expect(utc_date).to eq(Date.new(2024, 6, 15))
      expect(singapore_date).to eq(Date.new(2024, 6, 16))
    end
  end

  describe '.today_in_timezone' do
    it 'returns today in UTC' do
      travel_to Time.utc(2024, 6, 15, 12, 0, 0) do
        date = described_class.today_in_timezone('UTC')
        expect(date).to eq(Date.new(2024, 6, 15))
      end
    end

    it 'returns correct date for different timezone' do
      # At 2024-06-15 22:00 UTC, it's 2024-06-16 06:00 in Singapore
      travel_to Time.utc(2024, 6, 15, 22, 0, 0) do
        utc_today = described_class.today_in_timezone('UTC')
        singapore_today = described_class.today_in_timezone('Asia/Singapore')

        expect(utc_today).to eq(Date.new(2024, 6, 15))
        expect(singapore_today).to eq(Date.new(2024, 6, 16))
      end
    end
  end

  describe '.today_start_timestamp' do
    it 'returns start of today in the specified timezone' do
      travel_to Time.utc(2024, 6, 15, 12, 0, 0) do
        start_ts = described_class.today_start_timestamp('UTC')
        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 6, 15, 0, 0, 0))
      end
    end

    it 'returns correct start for different timezone' do
      travel_to Time.utc(2024, 6, 15, 22, 0, 0) do
        # In Singapore, it's already June 16th
        start_ts = described_class.today_start_timestamp('Asia/Singapore')
        # June 16th 00:00 in Singapore is June 15th 16:00 UTC
        expect(Time.at(start_ts).utc).to eq(Time.utc(2024, 6, 15, 16, 0, 0))
      end
    end
  end

  describe '.month_date_range' do
    it 'returns correct date range for a month' do
      range = described_class.month_date_range(2024, 2, 'UTC')

      expect(range.first).to eq(Date.new(2024, 2, 1))
      expect(range.last).to eq(Date.new(2024, 2, 29)) # 2024 is a leap year
    end

    it 'handles different timezones' do
      range = described_class.month_date_range(2024, 1, 'Asia/Singapore')

      expect(range.first).to eq(Date.new(2024, 1, 1))
      expect(range.last).to eq(Date.new(2024, 1, 31))
    end
  end

  describe '.validate_timezone' do
    it 'returns the timezone if valid' do
      expect(described_class.validate_timezone('America/New_York')).to eq('America/New_York')
      expect(described_class.validate_timezone('Europe/London')).to eq('Europe/London')
      expect(described_class.validate_timezone('Asia/Singapore')).to eq('Asia/Singapore')
    end

    it 'returns UTC for invalid timezone' do
      expect(described_class.validate_timezone('Invalid/Timezone')).to eq('UTC')
      expect(described_class.validate_timezone('Not A Timezone')).to eq('UTC')
    end

    it 'returns UTC for blank timezone' do
      expect(described_class.validate_timezone(nil)).to eq('UTC')
      expect(described_class.validate_timezone('')).to eq('UTC')
    end
  end

  describe '.valid_timezone?' do
    it 'returns true for valid timezones' do
      expect(described_class.valid_timezone?('UTC')).to be true
      expect(described_class.valid_timezone?('America/New_York')).to be true
      expect(described_class.valid_timezone?('Europe/Berlin')).to be true
    end

    it 'returns false for invalid timezones' do
      expect(described_class.valid_timezone?('Invalid/Timezone')).to be false
      expect(described_class.valid_timezone?(nil)).to be false
      expect(described_class.valid_timezone?('')).to be false
    end
  end
end
