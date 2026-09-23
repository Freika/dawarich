# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::MapMatchJob do
  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(100), end_at: Time.zone.at(110),
                   original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
                   map_matching_status: :pending)
  end
  let(:factory) { RGeo::Geographic.spherical_factory(srid: 4326) }
  let(:path) do
    points = [factory.point(13.4, 52.5), factory.point(13.41, 52.51)]
    factory.multi_line_string([factory.line_string(points)])
  end

  before do
    allow(DawarichSettings).to receive_messages(map_matching_enabled?: true, atlas_url: 'http://atlas:4567')
    create(:point, user:, track:, timestamp: 100, longitude: 13.4, latitude: 52.5)
    create(:point, user:, track:, timestamp: 110, longitude: 13.41, latitude: 52.51)
    create(:track_segment, :anchored, track:, transportation_mode: :walking,
                                      start_at: Time.zone.at(100), end_at: Time.zone.at(110))
  end

  it 'publishes a result only for the current digest' do
    input = MapMatching::Input.new(track)
    digest = MapMatching::Fingerprint.call(input)
    track.update!(map_matching_input_digest: digest)
    result = MapMatching::Processor::Result.new(
      status: :matched, path:, data: { schema_version: 1, segments: [] }
    )
    processor = instance_double(MapMatching::Processor, call: result)
    allow(MapMatching::Processor).to receive(:new).and_return(processor)

    described_class.perform_now(track.id, digest)

    expect(track.reload).to be_map_matching_status_matched
    expect(track.matched_path).to be_present
    expect(track.map_matched_at).to be_present
  end

  it 'publishes without changing the track revision the map editor checks, and invalidates its tiles' do
    input = MapMatching::Input.new(track)
    digest = MapMatching::Fingerprint.call(input)
    track.update!(map_matching_input_digest: digest)
    result = MapMatching::Processor::Result.new(
      status: :matched, path:, data: { schema_version: 1, segments: [] }
    )
    allow(MapMatching::Processor).to receive(:new).and_return(instance_double(MapMatching::Processor, call: result))
    tile_epoch = -> { Tracks::TileEpoch.etag_component(user.id, track.start_at.to_i, track.end_at.to_i) }
    epoch_before = tile_epoch.call

    expect { described_class.perform_now(track.id, digest) }.not_to(change { track.reload.lock_version })
    expect(track).to be_map_matching_status_matched
    expect(tile_epoch.call).not_to eq(epoch_before)
  end

  it 'records a terminal failure without changing the track revision' do
    input = MapMatching::Input.new(track)
    digest = MapMatching::Fingerprint.call(input)
    track.update!(map_matching_input_digest: digest)
    processor = instance_double(MapMatching::Processor)
    allow(MapMatching::Processor).to receive(:new).and_return(processor)
    allow(processor).to receive(:call).and_raise(
      MapMatching::Atlas::Client::ProviderError.new('boom', code: 'http_error', status: 418)
    )

    expect { described_class.perform_now(track.id, digest) }.not_to(change { track.reload.lock_version })
    expect(track).to be_map_matching_status_failed
  end

  it 'cannot overwrite a newer digest' do
    track.update!(map_matching_input_digest: 'newer')
    allow(MapMatching::Processor).to receive(:new)

    described_class.perform_now(track.id, 'older')

    expect(MapMatching::Processor).not_to have_received(:new)
    expect(track.reload).to be_map_matching_status_pending
    expect(track.map_matching_input_digest).to eq('newer')
  end

  it 'is a no-op if map matching is disabled while queued' do
    allow(DawarichSettings).to receive(:map_matching_enabled?).and_return(false)

    described_class.perform_now(track.id, 'digest')

    expect(track.reload).to be_map_matching_status_pending
  end

  it 'stores only a normalized terminal error' do
    input = MapMatching::Input.new(track)
    digest = MapMatching::Fingerprint.call(input)
    track.update!(map_matching_input_digest: digest)
    processor = instance_double(MapMatching::Processor)
    allow(MapMatching::Processor).to receive(:new).and_return(processor)
    allow(processor).to receive(:call).and_raise(
      MapMatching::Atlas::Client::ProviderError.new('upstream secret', code: 'http_error', status: 418)
    )

    described_class.perform_now(track.id, digest)

    expect(track.reload).to be_map_matching_status_failed
    expect(track.map_matching_data.dig('error', 'code')).to eq('http_error')
    expect(track.map_matching_data.to_json).not_to include('upstream secret')
  end
end
