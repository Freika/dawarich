# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::SyncTracks do
  let(:user) { create(:user) }
  let(:client) { AirTrail::Client.new('https://a.example', 'k') }
  let(:stored_track) { [[13.493, 52.351], [9.0, 51.5], [2.547, 49.009]] }

  def stub_summaries(*flights)
    stub_request(:get, 'https://a.example/api/v1/flights?limit=100')
      .to_return(status: 200, body: { data: flights, page: { nextCursor: nil } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def summary(id, updated_at)
    { id: id, track: { pointCount: 3, updatedAt: updated_at, sourceFormat: 'csv', sourceName: 'f.csv' } }
  end

  def stub_track(id, coordinates)
    stub_request(:get, "https://a.example/api/v1/flights/#{id}/track")
      .to_return(status: 200, body: { data: { flightId: id, coordinates: coordinates } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  it 'stores the track of a flight that has a new track in AirTrail' do
    flight = create(:flight, user: user, external_id: 1)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'))
    stub_track(1, [[13.493, 52.351, 40], [9.0, 51.5, 11_000], [2.547, 49.009, 90]])

    described_class.new(user, client).call

    flight.reload
    expect(flight.track_coordinates).to eq(stored_track)
    expect(flight.track_updated_at).to eq(Time.utc(2026, 10, 20, 8))
  end

  it 'does not download a track whose updatedAt has not changed' do
    create(:flight, user: user, external_id: 1, track_coordinates: stored_track,
                    track_updated_at: Time.utc(2026, 10, 20, 8))
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'))
    track = stub_track(1, [[0.0, 0.0], [1.0, 1.0]])

    described_class.new(user, client).call

    expect(track).not_to have_been_requested
  end

  it 'downloads the track again when AirTrail reports a newer updatedAt' do
    flight = create(:flight, user: user, external_id: 1, track_coordinates: stored_track,
                             track_updated_at: Time.utc(2026, 10, 20, 8))
    stub_summaries(summary(1, '2026-10-21T08:00:00.000Z'))
    stub_track(1, [[13.5, 52.4], [2.5, 49.0]])

    described_class.new(user, client).call

    flight.reload
    expect(flight.track_coordinates).to eq([[13.5, 52.4], [2.5, 49.0]])
    expect(flight.track_updated_at).to eq(Time.utc(2026, 10, 21, 8))
  end

  it 'keeps the stored track when AirTrail reports no track for the flight' do
    flight = create(:flight, user: user, external_id: 1, track_coordinates: stored_track,
                             track_updated_at: Time.utc(2026, 10, 20, 8))
    stub_summaries({ id: 1, track: nil })

    described_class.new(user, client).call

    expect(flight.reload.track_coordinates).to eq(stored_track)
  end

  it 'keeps stored tracks when AirTrail is older than 3.13 and has no v1 API' do
    flight = create(:flight, user: user, external_id: 1, track_coordinates: stored_track,
                             track_updated_at: Time.utc(2026, 10, 20, 8))
    stub_request(:get, 'https://a.example/api/v1/flights?limit=100').to_return(status: 404)

    expect { described_class.new(user, client).call }.not_to raise_error
    expect(flight.reload.track_coordinates).to eq(stored_track)
  end

  it 'stops downloading tracks when the API key lacks the tracks scope' do
    first = create(:flight, user: user, external_id: 1, track_coordinates: stored_track,
                            track_updated_at: Time.utc(2026, 10, 20, 8))
    create(:flight, user: user, external_id: 2)
    stub_summaries(summary(1, '2026-10-21T08:00:00.000Z'), summary(2, '2026-10-21T08:00:00.000Z'))
    forbidden = stub_request(:get, %r{https://a.example/api/v1/flights/\d+/track}).to_return(status: 403)

    expect { described_class.new(user, client).call }.not_to raise_error
    expect(forbidden).to have_been_requested.once
    expect(first.reload.track_coordinates).to eq(stored_track)
    expect(first.track_updated_at).to eq(Time.utc(2026, 10, 20, 8))
  end

  it 'stops downloading tracks when AirTrail rate-limits the requests' do
    create(:flight, user: user, external_id: 1)
    create(:flight, user: user, external_id: 2)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'), summary(2, '2026-10-20T08:00:00.000Z'))
    limited = stub_request(:get, %r{https://a.example/api/v1/flights/\d+/track}).to_return(status: 429)

    expect { described_class.new(user, client).call }.not_to raise_error
    expect(limited).to have_been_requested.once
  end

  it 'does not download a track again when its last download had too few valid points' do
    flight = create(:flight, user: user, external_id: 1, track_coordinates: stored_track)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'))
    track = stub_track(1, [[13.5, 52.4]])

    2.times { described_class.new(user, client).call }

    expect(track).to have_been_requested.once
    expect(flight.reload.track_coordinates).to eq(stored_track)
    expect(flight.track_updated_at).to eq(Time.utc(2026, 10, 20, 8))
  end

  it 'still downloads later tracks when one track fails on the AirTrail side' do
    create(:flight, user: user, external_id: 1)
    second = create(:flight, user: user, external_id: 2)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'), summary(2, '2026-10-20T08:00:00.000Z'))
    stub_request(:get, 'https://a.example/api/v1/flights/1/track').to_return(status: 500)
    stub_track(2, [[13.5, 52.4], [2.5, 49.0]])

    described_class.new(user, client).call

    expect(second.reload.track_coordinates).to eq([[13.5, 52.4], [2.5, 49.0]])
  end

  it 'still downloads later tracks when one track response is not valid JSON' do
    create(:flight, user: user, external_id: 1)
    second = create(:flight, user: user, external_id: 2)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'), summary(2, '2026-10-20T08:00:00.000Z'))
    stub_request(:get, 'https://a.example/api/v1/flights/1/track').to_return(status: 200, body: '<html>')
    stub_track(2, [[13.5, 52.4], [2.5, 49.0]])

    described_class.new(user, client).call

    expect(second.reload.track_coordinates).to eq([[13.5, 52.4], [2.5, 49.0]])
  end

  it 'stops downloading tracks once AirTrail stops responding' do
    create(:flight, user: user, external_id: 1)
    create(:flight, user: user, external_id: 2)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'), summary(2, '2026-10-20T08:00:00.000Z'))
    timeouts = stub_request(:get, %r{https://a.example/api/v1/flights/\d+/track}).to_timeout

    described_class.new(user, client).call

    expect(timeouts).to have_been_requested.once
  end

  it 'keeps the stored track when the track download times out' do
    flight = create(:flight, user: user, external_id: 1, track_coordinates: stored_track,
                             track_updated_at: Time.utc(2026, 10, 20, 8))
    stub_summaries(summary(1, '2026-10-21T08:00:00.000Z'))
    stub_request(:get, 'https://a.example/api/v1/flights/1/track').to_timeout

    expect { described_class.new(user, client).call }.not_to raise_error
    expect(flight.reload.track_coordinates).to eq(stored_track)
  end

  it 'simplifies a long track to at most 500 points, keeping both ends' do
    flight = create(:flight, user: user, external_id: 1)
    coordinates = Array.new(2_001) { |i| [i * 0.001, 50.0 + (i * 0.0001), 10_000] }
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'))
    stub_track(1, coordinates)

    described_class.new(user, client).call

    stored = flight.reload.track_coordinates
    expect(stored.size).to eq(500)
    expect(stored.first).to eq([0.0, 50.0])
    expect(stored.last).to eq([2.0, 50.2])
  end

  it 'ignores malformed points in a downloaded track' do
    flight = create(:flight, user: user, external_id: 1)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'))
    stub_track(1, [[13.493, 52.351], ['x', 1], [200.0, 10.0], 'junk', [2.547, 49.009]])

    described_class.new(user, client).call

    expect(flight.reload.track_coordinates).to eq([[13.493, 52.351], [2.547, 49.009]])
  end

  it 'does not touch flights of other users' do
    other = create(:flight, external_id: 1)
    stub_summaries(summary(1, '2026-10-20T08:00:00.000Z'))
    stub_track(1, [[13.5, 52.4], [2.5, 49.0]])

    described_class.new(user, client).call

    expect(other.reload.track_coordinates).to be_nil
  end
end
