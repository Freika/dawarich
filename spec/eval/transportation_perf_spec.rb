# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe 'Transportation detection performance', :eval do
  it 'classifies a 10k-point track in single-digit seconds' do
    user = create(:user)
    trip = TransportationTraceGenerator.trip(
      legs: [{ mode: :driving, duration_s: 50_000, dt_s: 5 }],
      start_time: Time.zone.parse('2026-02-01 08:00 UTC'), seed: 99
    )
    expect(trip[:points].size).to eq(10_000)

    track = create(:track, user: user,
                           start_at: Time.zone.at(trip[:points].first[:timestamp]),
                           end_at: Time.zone.at(trip[:points].last[:timestamp]))
    now = Time.current
    trip[:points].each_slice(2_000) do |slice|
      Point.insert_all(slice.map do |p|
        { user_id: user.id, track_id: track.id, timestamp: p[:timestamp],
          lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
          accuracy: p[:accuracy], velocity: p[:velocity].to_s,
          created_at: now, updated_at: now }
      end)
    end

    segments = nil
    elapsed = Benchmark.realtime do
      segments = TransportationModes::Detector.new(track).call
    end

    puts "10k-point detection: #{elapsed.round(2)}s, #{segments.size} segment(s)"
    expect(elapsed).to be < 10.0
    expect(segments).not_to be_empty
    # A constant-speed 14h cruise is kinematically ambiguous between highway
    # driving and rail (the documented no-map-context cap) — both are
    # acceptable here; this spec gates performance, not that distinction.
    expect(segments.map { |s| s[:mode] }.uniq - %i[driving train]).to be_empty
  end
end
