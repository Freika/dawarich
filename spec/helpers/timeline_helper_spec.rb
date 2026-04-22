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
end
