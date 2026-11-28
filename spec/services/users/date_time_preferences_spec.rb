# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DateTimePreferences do
  describe '.new' do
    it 'keeps valid values' do
      preferences = described_class.new(date_format: 'dd.mm.yyyy', time_format: '12h', first_day_of_week: 'sunday')

      expect(preferences.date_format).to eq('dd.mm.yyyy')
      expect(preferences.time_format).to eq('12h')
      expect(preferences.first_day_of_week).to eq('sunday')
    end

    it 'coerces invalid and missing values to the defaults' do
      preferences = described_class.new(date_format: 'bogus', time_format: nil, first_day_of_week: 42)

      expect(preferences.date_format).to eq('auto')
      expect(preferences.time_format).to eq('auto')
      expect(preferences.first_day_of_week).to eq('monday')
    end
  end

  describe '#week_start_symbol' do
    it 'returns the first day of week as a symbol' do
      expect(described_class.new(first_day_of_week: 'sunday').week_start_symbol).to eq(:sunday)
      expect(described_class::DEFAULT.week_start_symbol).to eq(:monday)
    end
  end

  describe '#default?' do
    it 'is true only when every preference is the default' do
      expect(described_class::DEFAULT).to be_default
      expect(described_class.new(time_format: '24h')).not_to be_default
    end
  end

  describe '#cache_key' do
    it 'differs whenever a preference differs' do
      keys = [
        described_class::DEFAULT,
        described_class.new(date_format: 'yyyy-mm-dd'),
        described_class.new(time_format: '12h'),
        described_class.new(first_day_of_week: 'sunday')
      ].map(&:cache_key)

      expect(keys.uniq.size).to eq(4)
    end
  end

  describe '.for' do
    it 'reads the preferences from the user settings' do
      user = create(:user, settings: { 'date_format' => 'yyyy-mm-dd', 'first_day_of_week' => 'sunday' })

      preferences = described_class.for(user)

      expect(preferences.date_format).to eq('yyyy-mm-dd')
      expect(preferences.time_format).to eq('auto')
      expect(preferences.first_day_of_week).to eq('sunday')
    end

    it 'returns the defaults without a user' do
      expect(described_class.for(nil)).to eq(described_class::DEFAULT)
    end
  end

  describe '.with' do
    let(:custom) { described_class.new(date_format: 'dd/mm/yyyy') }

    it 'activates the preferences for the block only' do
      inside = described_class.with(custom) { Current.date_time_preferences }

      expect(inside).to eq(custom)
      expect(Current.date_time_preferences).to eq(described_class::DEFAULT)
    end

    it 'accepts a user' do
      user = create(:user, settings: { 'time_format' => '12h' })

      inside = described_class.with(user) { Current.date_time_preferences.time_format }

      expect(inside).to eq('12h')
    end

    it 'restores the outer preferences when nested' do
      outer = described_class.new(time_format: '24h')

      described_class.with(outer) do
        described_class.with(custom) { nil }

        expect(Current.date_time_preferences).to eq(outer)
      end
    end
  end
end
