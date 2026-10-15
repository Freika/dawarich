# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::DistanceRace do
  let(:user) { create(:user) }

  def stat(year, month, days)
    create(:stat, user:, year:, month:, distance: days.values.sum, daily_distance: days.transform_keys(&:to_s))
  end

  def race(year, today:)
    described_class.new(user.stats.where(year:), user.stats.where(year: year - 1), year, today:).call
  end

  it 'adds the distance up day by day and stops at today for the current year' do
    stat(2026, 1, { 1 => 1_000, 3 => 2_000 })
    stat(2026, 2, { 1 => 5_000 })

    result = race(2026, today: Date.new(2026, 2, 1))

    expect(result.current.size).to eq(32)
    expect(result.current.first(4)).to eq([1_000, 1_000, 3_000, 3_000])
    expect(result.current.last).to eq(8_000)
  end

  it 'runs a past year to its last day' do
    stat(2025, 12, { 31 => 4_000 })

    result = race(2025, today: Date.new(2026, 3, 1))

    expect(result.current.size).to eq(365)
    expect(result.current.last).to eq(4_000)
  end

  it 'compares with the same day of the previous year and reports the lead' do
    stat(2026, 1, { 1 => 3_000 })
    stat(2025, 1, { 1 => 1_000, 2 => 500 })
    stat(2025, 6, { 1 => 9_000 })

    result = race(2026, today: Date.new(2026, 1, 2))

    expect(result.previous.size).to eq(365)
    expect(result.previous.last).to eq(10_500)
    expect(result.lead).to eq(3_000 - 1_500)
  end

  it 'lines a leap year up with the shorter previous year by day of year' do
    stat(2024, 12, { 31 => 7_000 })
    stat(2023, 12, { 31 => 2_000 })

    result = race(2024, today: Date.new(2025, 1, 5))

    expect(result.current.size).to eq(366)
    expect(result.lead).to eq(7_000 - 2_000)
  end

  it 'compares with the same calendar day when the previous year is a leap year' do
    stat(2024, 2, { 29 => 1_000 })
    stat(2024, 3, { 1 => 2_000 })
    stat(2025, 3, { 1 => 5_000 })

    result = race(2025, today: Date.new(2025, 3, 1))

    expect(result.previous.size).to eq(365)
    expect(result.lead).to eq(5_000 - 3_000)
  end

  describe '.for' do
    it 'keeps the previous year for a user without a data window' do
      this_year = Time.current.year
      stat(this_year, 1, { 1 => 3_000 })
      stat(this_year - 1, 12, { 31 => 1_000 })

      expect(described_class.for(user, this_year).previous).to be_present
    end
  end

  it 'has no previous line and no lead without data for the previous year' do
    stat(2026, 1, { 1 => 3_000 })

    result = race(2026, today: Date.new(2026, 1, 2))

    expect(result.previous).to be_nil
    expect(result.lead).to be_nil
  end

  it 'has nothing to draw for a year that has not started' do
    expect(race(2027, today: Date.new(2026, 5, 1))).to be_nil
  end
end
