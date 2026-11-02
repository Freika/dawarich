# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TripsHelper, type: :helper do
  describe '#planned_note_time' do
    def note_time(value, time_format)
      Users::DateTimePreferences.with(Users::DateTimePreferences.new(time_format:)) do
        helper.planned_note_time(value)
      end
    end

    it 'renders the stored clock time with the time format' do
      expect(note_time('14:05:00', 'auto')).to eq('14:05')
      expect(note_time('14:05:00', '12h')).to eq('2:05 PM')
      expect(note_time('9:30', '12h')).to eq('9:30 AM')
    end

    it 'keeps values that are not a clock time' do
      expect(note_time('morning', '12h')).to eq('morning')
    end
  end

  describe '#trip_poster_stats' do
    let(:trip) { build(:trip, distance: 27_430) }

    it 'shows the stored distance in kilometres without dates' do
      expect(helper.trip_poster_stats(trip, 'km')).to eq('27.4 km')
    end

    it 'follows a miles distance unit' do
      expect(helper.trip_poster_stats(trip, 'mi')).to eq('17 mi')
    end

    it 'rounds long distances to whole units with a thousands delimiter' do
      trip.distance = 1_234_567

      expect(helper.trip_poster_stats(trip, 'km')).to eq('1,235 km')
    end

    it 'formats the number for the current locale' do
      I18n.with_locale(:de) do
        expect(helper.trip_poster_stats(trip, 'km')).to eq('27,4 km')
      end
    end

    it 'is nil when the distance rounds to zero' do
      trip.distance = 20

      expect(helper.trip_poster_stats(trip, 'km')).to be_nil
    end

    it 'keeps a sub-kilometre distance in a comma-decimal locale' do
      trip.distance = 100

      I18n.with_locale(:de) { expect(helper.trip_poster_stats(trip, 'km')).to eq('0,1 km') }
    end

    it 'is nil until the trip distance has been calculated' do
      trip.distance = nil

      expect(helper.trip_poster_stats(trip, 'km')).to be_nil
    end
  end
end
