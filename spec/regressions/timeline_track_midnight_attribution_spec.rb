# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Timeline daily attribution for tracks crossing midnight' do
  let(:tz) { 'Europe/Berlin' }
  let(:user) { create(:user, settings: { 'timezone' => tz }) }

  let(:day_a) { Date.new(2026, 4, 27) }
  let(:day_b) { Date.new(2026, 4, 28) }

  let!(:overnight_track) do
    Time.use_zone(tz) do
      create(
        :track,
        user: user,
        start_at: Time.zone.local(2026, 4, 27, 23, 30),
        end_at: Time.zone.local(2026, 4, 28, 2, 0),
        distance: 180_000,
        duration: 9_000
      )
    end
  end

  describe Timeline::DayAssembler do
    def assemble(date)
      Time.use_zone(tz) do
        described_class.new(
          user,
          start_at: date.in_time_zone(tz).beginning_of_day.iso8601,
          end_at: date.in_time_zone(tz).end_of_day.iso8601
        ).call
      end
    end

    it 'distributes overnight track distance across both calendar days in the user timezone' do
      day_a_entry = assemble(day_a).find { |d| d[:date] == day_a.to_s }
      day_b_entry = assemble(day_b).find { |d| d[:date] == day_b.to_s }

      day_a_distance = day_a_entry&.dig(:summary, :total_distance) || 0
      day_b_distance = day_b_entry&.dig(:summary, :total_distance) || 0
      total_km = (overnight_track.distance / 1000.0).round(1)

      expect(day_a_distance).to be > 0,
                                "Day A (#{day_a}) should have some distance, got #{day_a_distance}"
      expect(day_b_distance).to be > 0,
                                "Day B (#{day_b}) should also have some distance because the track " \
                                "extends past midnight, got #{day_b_distance}. " \
                                'Currently the entire track is attributed to its start day, leaving ' \
                                'the continuation day with zero km even though points are present on the map.'
      expect(day_a_distance + day_b_distance).to be_within(0.2).of(total_km)
      expect(day_b_distance).to be > day_a_distance,
                                'Most of the track happened after midnight, so Day B should hold the ' \
                                "larger share. Got Day A=#{day_a_distance} Day B=#{day_b_distance}."
    end

    it 'does not include the prior-day track polyline in the continuation-day bounds' do
      day_b_entry = assemble(day_b).find { |d| d[:date] == day_b.to_s }
      expect(day_b_entry[:bounds]).to be_nil
    end

    it 'returns only the requested day even when a track spreads shares to adjacent days' do
      result = assemble(day_b)
      expect(result.map { |d| d[:date] }).to eq([day_b.to_s])
    end

    it 'flags the continuation-day journey entry with continuation_of_date and pro-rata day_distance / day_duration' do
      day_b_entry = assemble(day_b).find { |d| d[:date] == day_b.to_s }
      journey = day_b_entry[:entries].find { |e| e[:type] == 'journey' }

      expect(journey[:continuation_of_date]).to eq(day_a.to_s)
      expect(journey[:day_distance]).to be < journey[:distance]
      expect(journey[:day_duration]).to be < journey[:duration]
      expect(journey[:day_distance]).to be > 0
      expect(journey[:day_duration]).to be > 0
    end

    it 'leaves continuation_of_date / day_distance / day_duration nil on the originating day' do
      day_a_entry = assemble(day_a).find { |d| d[:date] == day_a.to_s }
      journey = day_a_entry[:entries].find { |e| e[:type] == 'journey' }

      expect(journey[:continuation_of_date]).to be_nil
      expect(journey[:day_distance]).to be_nil
      expect(journey[:day_duration]).to be_nil
    end

    it 'sorts a continuation-day journey to its arrival time within the day' do
      pre_arrival_place = create(:place, :with_geodata, name: 'Gas station', latitude: 52.45, longitude: 13.30)
      morning_place = create(:place, :with_geodata, name: 'Cafe', latitude: 52.52, longitude: 13.40)
      # Visit during the trip continuation (00:30, before the 02:00 arrival).
      create(:visit,
             user: user,
             place: pre_arrival_place,
             name: 'Gas station',
             started_at: Time.zone.local(2026, 4, 28, 0, 30),
             ended_at: Time.zone.local(2026, 4, 28, 0, 45),
             duration: 15)
      # Visit after the trip arrives.
      create(:visit,
             user: user,
             place: morning_place,
             name: 'Cafe',
             started_at: Time.zone.local(2026, 4, 28, 8, 0),
             ended_at: Time.zone.local(2026, 4, 28, 9, 0),
             duration: 60)

      day_b_entry = assemble(day_b).find { |d| d[:date] == day_b.to_s }
      ordered = day_b_entry[:entries].map { |e| [e[:type], e[:name] || e[:dominant_mode]] }
      expect(ordered).to eq([
                              ['visit', 'Gas station'],
                              ['journey', overnight_track.dominant_mode],
                              ['visit', 'Cafe']
                            ]),
                         'Continuation journey should sort to its 02:00 arrival time, between the ' \
                         "00:30 visit and the 08:00 visit. Got #{ordered.inspect}"
    end

    it 'preserves track_count as start-day-only in the calendar grid' do
      summary = Time.use_zone(tz) do
        Timeline::MonthSummary.new(user: user, month: Date.new(2026, 4, 1)).call
      end
      cells = summary[:weeks].flatten.index_by { |c| c[:date] }
      expect(cells['2026-04-27'][:track_count]).to eq(1)
      expect(cells['2026-04-28'][:track_count]).to eq(0)
      expect(cells['2026-04-28'][:tracked_seconds]).to be > 0
    end
  end

  describe Timeline::MonthSummary do
    subject(:summary) do
      Time.use_zone(tz) do
        described_class.new(user: user, month: Date.new(2026, 4, 1)).call
      end
    end

    it 'reports tracked seconds on both calendar days for an overnight track' do
      cells_by_date = summary[:weeks].flatten.index_by { |c| c[:date] }
      day_a_seconds = cells_by_date['2026-04-27']&.dig(:tracked_seconds).to_i
      day_b_seconds = cells_by_date['2026-04-28']&.dig(:tracked_seconds).to_i

      expect(day_a_seconds).to be > 0,
                               "Day A cell should have tracked_seconds > 0, got #{day_a_seconds}"
      expect(day_b_seconds).to be > 0,
                               'Day B cell should also have tracked_seconds > 0 because the track ' \
                               "ends after midnight, got #{day_b_seconds}. " \
                               'Currently the calendar heat-map attributes the full duration to the ' \
                               'start day only.'
    end
  end
end
