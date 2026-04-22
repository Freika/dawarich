# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimelineHelper, type: :helper do
  describe '#timeline_all_day?' do
    context 'when visit is nil' do
      it 'returns false' do
        expect(helper.timeline_all_day?(nil)).to be false
      end
    end

    context 'when visit duration is >= 23 hours (in minutes)' do
      it 'returns true for exactly 23h' do
        visit = instance_double(Visit, duration: 23 * 60, started_at: Time.zone.local(2026, 1, 1, 10, 0),
                                       ended_at: Time.zone.local(2026, 1, 2, 9, 0))
        expect(helper.timeline_all_day?(visit)).to be true
      end

      it 'returns true for 24h' do
        visit = instance_double(Visit, duration: 24 * 60, started_at: Time.zone.local(2026, 1, 1, 10, 0),
                                       ended_at: Time.zone.local(2026, 1, 2, 10, 0))
        expect(helper.timeline_all_day?(visit)).to be true
      end
    end

    context 'when visit duration is just under 23 hours' do
      it 'returns false for 22h 59m' do
        visit = instance_double(Visit, duration: (22 * 60) + 59,
                                       started_at: Time.zone.local(2026, 1, 1, 10, 0),
                                       ended_at: Time.zone.local(2026, 1, 2, 8, 59))
        expect(helper.timeline_all_day?(visit)).to be false
      end
    end

    context 'when visit starts at midnight and spans nearly a full day' do
      it 'returns true when starts at hour 0 and covers >= 23 hours' do
        started = Time.zone.local(2026, 1, 1, 0, 0)
        visit = instance_double(Visit, duration: 100, started_at: started, ended_at: started + 23.hours)
        expect(helper.timeline_all_day?(visit)).to be true
      end

      it 'returns false when starts at hour 0 but spans less than 23 hours' do
        started = Time.zone.local(2026, 1, 1, 0, 0)
        visit = instance_double(Visit, duration: 60, started_at: started, ended_at: started + 1.hour)
        expect(helper.timeline_all_day?(visit)).to be false
      end
    end
  end

  describe '#format_dwell_minutes' do
    it 'returns "0m" for 0 minutes' do
      expect(helper.format_dwell_minutes(0)).to eq('0m')
    end

    it 'returns "0m" for negative minutes' do
      expect(helper.format_dwell_minutes(-5)).to eq('0m')
    end

    it 'returns "45m" for 45 minutes' do
      expect(helper.format_dwell_minutes(45)).to eq('45m')
    end

    it 'returns "1h" for 60 minutes' do
      expect(helper.format_dwell_minutes(60)).to eq('1h')
    end

    it 'returns "1h 7m" for 67 minutes' do
      expect(helper.format_dwell_minutes(67)).to eq('1h 7m')
    end

    it 'returns "2h 30m" for 150 minutes' do
      expect(helper.format_dwell_minutes(150)).to eq('2h 30m')
    end

    it 'coerces string input via to_i' do
      expect(helper.format_dwell_minutes('90')).to eq('1h 30m')
    end
  end

  describe '#heat_bucket' do
    it 'returns 0 for 0 seconds' do
      expect(helper.heat_bucket(0)).to eq(0)
    end

    it 'returns 0 for nil' do
      expect(helper.heat_bucket(nil)).to eq(0)
    end

    it 'returns 1 for 1 hour (3600s)' do
      expect(helper.heat_bucket(3600)).to eq(1)
    end

    it 'returns 1 for just under 2 hours' do
      expect(helper.heat_bucket(2 * 3600 - 1)).to eq(1)
    end

    it 'returns 2 for 3 hours' do
      expect(helper.heat_bucket(3 * 3600)).to eq(2)
    end

    it 'returns 3 for 6 hours' do
      expect(helper.heat_bucket(6 * 3600)).to eq(3)
    end

    it 'returns 4 for 10 hours' do
      expect(helper.heat_bucket(10 * 3600)).to eq(4)
    end

    it 'returns 5 for 13 hours' do
      expect(helper.heat_bucket(13 * 3600)).to eq(5)
    end

    it 'returns 5 for 24 hours' do
      expect(helper.heat_bucket(24 * 3600)).to eq(5)
    end
  end

  describe '#visit_entry_display_name' do
    it 'returns entry name when present' do
      entry = { name: 'Home', place: { name: 'Place Name' } }
      expect(helper.visit_entry_display_name(entry)).to eq('Home')
    end

    it 'falls back to place name when entry name is blank' do
      entry = { name: '', place: { name: 'Place Name' } }
      expect(helper.visit_entry_display_name(entry)).to eq('Place Name')
    end

    it 'falls back to place name when entry name is nil' do
      entry = { name: nil, place: { name: 'Place Name' } }
      expect(helper.visit_entry_display_name(entry)).to eq('Place Name')
    end

    it 'returns "Unnamed" when both entry name and place name are missing' do
      entry = { name: nil, place: nil }
      expect(helper.visit_entry_display_name(entry)).to eq('Unnamed')
    end

    it 'returns "Unnamed" when place exists but has no name' do
      entry = { name: nil, place: { name: nil } }
      expect(helper.visit_entry_display_name(entry)).to eq('Unnamed')
    end
  end

  describe '#visit_entry_all_day?' do
    it 'returns true when duration >= 23 hours' do
      entry = { started_at: '2026-01-01T10:00:00Z', ended_at: '2026-01-02T09:00:00Z', duration: 23 * 60 }
      expect(helper.visit_entry_all_day?(entry)).to be true
    end

    it 'returns true when starts at midnight and spans >= 23 hours' do
      entry = { started_at: '2026-01-01T00:00:00', ended_at: '2026-01-01T23:00:00', duration: 100 }
      expect(helper.visit_entry_all_day?(entry)).to be true
    end

    it 'returns false for a short visit' do
      entry = { started_at: '2026-01-01T10:00:00', ended_at: '2026-01-01T11:00:00', duration: 60 }
      expect(helper.visit_entry_all_day?(entry)).to be false
    end
  end

  describe '#visit_entry_times' do
    it 'returns parsed times and HH:MM labels' do
      entry = { started_at: '2026-01-01T10:30:00', ended_at: '2026-01-01T12:45:00' }
      result = helper.visit_entry_times(entry)

      expect(result[:start_label]).to eq('10:30')
      expect(result[:end_label]).to eq('12:45')
      expect(result[:start_at]).to be_a(Time)
      expect(result[:ended_at]).to be_a(Time)
    end
  end

  describe '#visit_entry_status' do
    it 'returns the entry status when present' do
      expect(helper.visit_entry_status(status: 'suggested')).to eq('suggested')
    end

    it 'defaults to "confirmed" when status is blank' do
      expect(helper.visit_entry_status(status: '')).to eq('confirmed')
    end

    it 'defaults to "confirmed" when status is nil' do
      expect(helper.visit_entry_status(status: nil)).to eq('confirmed')
    end

    it 'defaults to "confirmed" when key is missing' do
      expect(helper.visit_entry_status({})).to eq('confirmed')
    end
  end

  describe '#day_label' do
    it 'formats the date as "Weekday, Month Day"' do
      expect(helper.day_label(date: '2026-01-03')).to eq('Saturday, January 3')
    end
  end

  describe '#day_total_visits_count' do
    it 'sums confirmed, suggested, and declined counts' do
      day = { summary: { confirmed_count: 3, suggested_count: 2, declined_count: 1 } }
      expect(helper.day_total_visits_count(day)).to eq(6)
    end

    it 'coerces nil counts to 0' do
      day = { summary: { confirmed_count: nil, suggested_count: 2, declined_count: nil } }
      expect(helper.day_total_visits_count(day)).to eq(2)
    end
  end

  describe '#day_bounds_json' do
    it 'returns JSON when bounds present' do
      day = { bounds: { north: 1, south: 2 } }
      expect(helper.day_bounds_json(day)).to eq('{"north":1,"south":2}')
    end

    it 'returns nil when bounds missing' do
      expect(helper.day_bounds_json(bounds: nil)).to be_nil
    end
  end

  describe '#calendar_month_nav' do
    it 'returns prev/next month strings and a formatted title' do
      result = helper.calendar_month_nav(month: '2026-03')

      expect(result[:prev]).to eq('2026-02')
      expect(result[:next]).to eq('2026-04')
      expect(result[:title]).to eq('March 2026')
    end

    it 'handles year boundaries' do
      result = helper.calendar_month_nav(month: '2026-01')

      expect(result[:prev]).to eq('2025-12')
      expect(result[:next]).to eq('2026-02')
    end
  end

  describe '#calendar_weekday_labels' do
    it 'returns Mon-Sun single-letter labels' do
      expect(helper.calendar_weekday_labels).to eq(%w[M T W T F S S])
    end
  end

  describe '#calendar_day_number' do
    it 'returns the day of month integer' do
      expect(helper.calendar_day_number(date: '2026-03-15')).to eq(15)
    end
  end

  describe '#calendar_cell_classes' do
    it 'includes base cal-cell and heat bucket class for an in-month cell with tracked time' do
      cell = { tracked_seconds: 3600, suggested_count: 0, in_month: true, disabled: false }
      result = helper.calendar_cell_classes(cell)

      expect(result).to include('cal-cell')
      expect(result).to match(/heat-\d/)
    end

    it 'adds has-suggestions when suggested_count is positive' do
      cell = { tracked_seconds: 0, suggested_count: 2, in_month: true, disabled: false }
      expect(helper.calendar_cell_classes(cell)).to include('has-suggestions')
    end

    it 'adds out-of-month when cell is not in the current month' do
      cell = { tracked_seconds: 0, suggested_count: 0, in_month: false, disabled: false }
      expect(helper.calendar_cell_classes(cell)).to include('out-of-month')
    end

    it 'adds disabled when cell is disabled' do
      cell = { tracked_seconds: 0, suggested_count: 0, in_month: true, disabled: true }
      expect(helper.calendar_cell_classes(cell)).to include('disabled')
    end

    it 'applies dark text for low heat buckets and light text for high ones' do
      low = { tracked_seconds: 0, suggested_count: 0, in_month: true, disabled: false }
      high = { tracked_seconds: 12 * 3600, suggested_count: 0, in_month: true, disabled: false }

      expect(helper.calendar_cell_classes(low)).to include('cal-cell--dark-text')
      expect(helper.calendar_cell_classes(high)).to include('cal-cell--light-text')
    end
  end
end
