# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::TracksBuilder do
  let(:user) { create(:user) }
  let(:start_at) { Time.zone.parse('2026-04-01T00:00:00Z') }
  let(:end_at) { Time.zone.parse('2026-04-30T23:59:59Z') }

  def build
    described_class.new(user: user, start_at: start_at, end_at: end_at).call
  end

  def linestring(coords)
    "LINESTRING(#{coords.map { |lon, lat| "#{lon} #{lat}" }.join(', ')})"
  end

  it 'returns nil when no tracks overlap the range' do
    create(:track, user: user, start_at: Time.zone.parse('2026-05-02T10:00:00Z'),
                   end_at: Time.zone.parse('2026-05-02T11:00:00Z'))

    expect(build).to be_nil
  end

  it 'returns one segment per overlapping track, ordered by start_at' do
    create(:track, user: user,
                   start_at: Time.zone.parse('2026-04-10T10:00:00Z'),
                   end_at: Time.zone.parse('2026-04-10T11:00:00Z'),
                   original_path: linestring([[13.50, 52.50], [13.51, 52.51]]))
    create(:track, user: user,
                   start_at: Time.zone.parse('2026-04-05T10:00:00Z'),
                   end_at: Time.zone.parse('2026-04-05T11:00:00Z'),
                   original_path: linestring([[13.40, 52.40], [13.41, 52.41]]))

    result = build

    expect(result['type']).to eq('MultiLineString')
    expect(result['coordinates']).to eq([
                                          [[13.40, 52.40], [13.41, 52.41]],
                                          [[13.50, 52.50], [13.51, 52.51]]
                                        ])
  end

  it 'includes tracks partially overlapping the range' do
    create(:track, user: user,
                   start_at: Time.zone.parse('2026-03-31T23:00:00Z'),
                   end_at: Time.zone.parse('2026-04-01T01:00:00Z'),
                   original_path: linestring([[13.40, 52.40], [13.41, 52.41]]))

    expect(build['coordinates'].size).to eq(1)
  end

  it 'excludes tracks belonging to other users' do
    create(:track, start_at: start_at + 1.day, end_at: start_at + 1.day + 1.hour)

    expect(build).to be_nil
  end

  it 'keeps every vertex without sampling' do
    stub_const('Posters::TracksBuilder::MAX_POINTS', 10) if defined?(Posters::TracksBuilder::MAX_POINTS)
    coords = Array.new(50) { |i| [13.0 + (i * 0.0001), 52.0] }
    create(:track, user: user, start_at: start_at + 1.day, end_at: start_at + 1.day + 1.hour,
                   original_path: linestring(coords))

    expect(build['coordinates'].sum(&:size)).to eq(50)
  end
end
