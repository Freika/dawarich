# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::DayBoundary do
  def boundary(timezone, split: true)
    described_class.new(build(:user, settings: { 'timezone' => timezone, 'split_tracks_at_midnight' => split }))
  end

  it 'never crosses when the user keeps the setting off' do
    berlin = boundary('Europe/Berlin', split: false)

    expect(berlin.crosses?(Time.utc(2025, 1, 14, 22, 59), Time.utc(2025, 1, 14, 23, 1))).to be(false)
  end

  it 'crosses at local midnight rather than UTC midnight' do
    berlin = boundary('Europe/Berlin')

    expect(berlin.crosses?(Time.utc(2025, 1, 14, 22, 59), Time.utc(2025, 1, 14, 23, 1))).to be(true)
    expect(berlin.crosses?(Time.utc(2025, 1, 14, 23, 1), Time.utc(2025, 1, 15, 0, 30))).to be(false)
  end

  it 'crosses at local midnight in a timezone behind UTC' do
    new_york = boundary('America/New_York')

    expect(new_york.crosses?(Time.utc(2025, 1, 15, 4, 59).to_i, Time.utc(2025, 1, 15, 5, 1).to_i)).to be(true)
    expect(new_york.crosses?(Time.utc(2025, 1, 14, 23, 59).to_i, Time.utc(2025, 1, 15, 0, 1).to_i)).to be(false)
  end

  it 'crosses when clocks jump forward at midnight and keeps the shortened day together' do
    beirut = boundary('Asia/Beirut')

    expect(beirut.crosses?(Time.utc(2026, 3, 28, 21, 59), Time.utc(2026, 3, 28, 22, 1))).to be(true)
    expect(beirut.crosses?(Time.utc(2026, 3, 28, 22, 1), Time.utc(2026, 3, 29, 20, 59))).to be(false)
  end
end
