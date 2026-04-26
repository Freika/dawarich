# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlacesHelper, type: :helper do
  describe '#place_dwell_stats' do
    let(:user) { create(:user) }
    let(:place) { create(:place, user: user, city: 'Berlin', country: 'Germany') }

    context 'with no visits' do
      it 'returns zero stats and blank location line when both city and country absent' do
        placeless = create(:place, user: user, city: nil, country: nil)
        stats = helper.place_dwell_stats(placeless)

        expect(stats[:visit_count]).to eq(0)
        expect(stats[:total_hours]).to eq(0.0)
        expect(stats[:avg_label]).to eq('0h 0m')
        expect(stats[:location_line]).to eq('')
      end

      it 'returns zero stats for a place with no visits' do
        stats = helper.place_dwell_stats(place)

        expect(stats[:visit_count]).to eq(0)
        expect(stats[:total_hours]).to eq(0.0)
        expect(stats[:avg_label]).to eq('0h 0m')
      end
    end

    context 'with visits' do
      before do
        create(:visit, place: place, user: user, duration: 90, started_at: 1.day.ago, ended_at: 1.day.ago + 90.minutes)
        create(:visit, place: place, user: user, duration: 30,
                       started_at: 2.days.ago, ended_at: 2.days.ago + 30.minutes)
      end

      it 'computes visit count, total hours, and average dwell label' do
        stats = helper.place_dwell_stats(place)

        expect(stats[:visit_count]).to eq(2)
        expect(stats[:total_hours]).to eq(2.0)
        expect(stats[:avg_label]).to eq('1h 0m')
      end
    end

    it 'joins city and country with a comma' do
      stats = helper.place_dwell_stats(place)
      expect(stats[:location_line]).to eq('Berlin, Germany')
    end

    it 'omits blank location parts' do
      place_city_only = create(:place, user: user, city: 'Berlin', country: '')
      stats = helper.place_dwell_stats(place_city_only)
      expect(stats[:location_line]).to eq('Berlin')
    end

    it 'exposes the primary tag' do
      tag = create(:tag, user: user)
      place.tags << tag

      stats = helper.place_dwell_stats(place)
      expect(stats[:primary_tag]).to eq(tag)
    end

    it 'returns nil primary_tag when no tags present' do
      stats = helper.place_dwell_stats(place)
      expect(stats[:primary_tag]).to be_nil
    end
  end

  describe '#place_visit_time_range' do
    let(:user) { create(:user) }
    let(:place) { create(:place, user: user) }

    it 'returns start/end/date labels and duration label' do
      started = Time.zone.local(2026, 3, 15, 9, 30)
      ended = started + 150.minutes
      visit = create(:visit, place: place, user: user, started_at: started, ended_at: ended, duration: 150)

      result = helper.place_visit_time_range(visit)

      expect(result[:start_label]).to eq('09:30')
      expect(result[:end_label]).to eq('12:00')
      expect(result[:date_label]).to eq('2026-03-15')
      expect(result[:duration_label]).to eq('2h 30m')
    end
  end
end
