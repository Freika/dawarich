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
      days_a = assemble(day_a)
      days_b = assemble(day_b)

      day_a_distance = days_a.first&.dig(:summary, :total_distance) || 0
      day_b_distance = days_b.first&.dig(:summary, :total_distance) || 0

      expect(day_a_distance).to be > 0,
                                "Day A (#{day_a}) should have some distance, got #{day_a_distance}"
      expect(day_b_distance).to be > 0,
                                "Day B (#{day_b}) should also have some distance because the track " \
                                "extends past midnight, got #{day_b_distance}. " \
                                'Currently the entire track is attributed to its start day, leaving ' \
                                'the continuation day with zero km even though points are present on the map.'
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
