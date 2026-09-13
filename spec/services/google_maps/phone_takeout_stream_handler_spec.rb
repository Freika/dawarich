# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::PhoneTakeoutStreamHandler do
  def parse(payload, entries:, profiles:)
    handler = described_class.new(
      on_entry: ->(section, value) { entries << [section, value] },
      on_profile: ->(profile) { profiles << profile }
    )
    Oj::Parser.new(:saj, handler:).load(StringIO.new(Oj.dump(payload, mode: :compat)))
  end

  it 'streams semantic segments and raw signals independently' do
    semantic_segment = { 'startTime' => '2024-06-15T09:00:00Z', 'timelinePath' => [] }
    raw_signal = { 'position' => { 'LatLng' => '48.8566,2.3522' } }
    entries = []

    parse(
      {
        'semanticSegments' => [semantic_segment],
        'rawSignals' => [raw_signal],
        'metadata' => [{ 'source' => 'Synthetic' }]
      },
      entries:,
      profiles: []
    )

    expect(entries).to eq([[:semantic_segment, semantic_segment],
                           [:raw_signal, raw_signal]])
  end

  it 'streams every entry from a root-array export' do
    raw_entries = [
      { 'startTime' => '2024-06-15T09:00:00Z', 'timelinePath' => [] },
      { 'startTime' => '2024-06-15T10:00:00Z', 'visit' => {} }
    ]
    entries = []

    parse(raw_entries, entries:, profiles: [])

    expect(entries).to eq(raw_entries.map { |entry| [:raw_array, entry] })
  end

  it 'captures the user location profile without retaining other root sections' do
    profile = {
      'frequentPlaces' => [{ 'label' => 'HOME', 'placeLocation' => '48.8566,2.3522' }]
    }
    profiles = []

    parse(
      { 'metadata' => [{ 'source' => 'Synthetic' }], 'userLocationProfile' => profile },
      entries: [],
      profiles:
    )

    expect(profiles).to eq([profile])
  end
end
