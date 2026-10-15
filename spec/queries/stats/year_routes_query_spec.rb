# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::YearRoutesQuery do
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

  def track(path, start_at)
    create(:track, user:, original_path: path, start_at:, end_at: start_at + 1.hour)
  end

  it 'returns the routes travelled in the year as lines of longitude and latitude' do
    track('LINESTRING(13.40 52.52, 13.74 51.05, 14.42 50.08)', Time.utc(2025, 5, 1, 10))
    track('LINESTRING(2.35 48.86, 4.84 45.76)', Time.utc(2025, 8, 1, 10))

    lines = described_class.new(user, 2025).call

    expect(lines.size).to eq(2)
    expect(lines.flatten(1)).to include([13.4, 52.52], [14.42, 50.08], [2.35, 48.86])
  end

  it 'leaves out tracks from other years, using the user time zone for the edges' do
    track('LINESTRING(13.40 52.52, 14.42 50.08)', Time.utc(2025, 6, 1, 10))
    track('LINESTRING(2.35 48.86, 4.84 45.76)', Time.utc(2024, 12, 31, 23, 30))
    track('LINESTRING(10.00 53.55, 12.57 55.68)', Time.utc(2025, 12, 31, 23, 30))

    points = described_class.new(user, 2025).call.flatten(1)

    expect(points).to include([13.4, 52.52], [2.35, 48.86])
    expect(points).not_to include([10.0, 53.55])
  end

  it 'returns nothing for a year without tracks' do
    expect(described_class.new(user, 2025).call).to be_nil
  end

  it 'respects the Lite data window' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update!(plan: :lite)
    old = 2.years.ago.year
    track('LINESTRING(13.40 52.52, 14.42 50.08)', Time.utc(old, 6, 1, 10))

    expect(described_class.new(user, old).call).to be_nil
  end

  it 'keeps few coordinates for a long, dense route' do
    path = (0..2_000).map { |i| "#{13 + (i * 0.001)} #{52 + (Math.sin(i / 50.0) * 0.01)}" }.join(', ')
    track("LINESTRING(#{path})", Time.utc(2025, 3, 1, 10))

    lines = described_class.new(user, 2025).call

    expect(lines.sum(&:size)).to be < 500
  end
end
