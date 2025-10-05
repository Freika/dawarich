# frozen_string_literal: true

require 'rails_helper'
require 'oj'

RSpec.describe JsonStreamHandler do
  let(:processor) { double('StreamProcessor') }
  let(:handler) { described_class.new(processor) }

  before do
    allow(processor).to receive(:handle_section)
    allow(processor).to receive(:handle_stream_value)
    allow(processor).to receive(:finish_stream)
  end

  it 'streams configured sections and delegates other values immediately' do
    payload = {
      'counts' => { 'places' => 2, 'visits' => 1, 'points' => 1 },
      'settings' => { 'theme' => 'dark' },
      'areas' => [{ 'name' => 'Home' }],
      'places' => [
        { 'name' => 'Cafe', 'latitude' => 1.0, 'longitude' => 2.0 },
        { 'name' => 'Library', 'latitude' => 3.0, 'longitude' => 4.0 }
      ],
      'visits' => [
        {
          'name' => 'Morning Coffee',
          'started_at' => '2025-01-01T09:00:00Z',
          'ended_at' => '2025-01-01T10:00:00Z'
        }
      ],
      'points' => [
        { 'timestamp' => 1, 'lonlat' => 'POINT(2 1)' }
      ]
    }

    Oj.saj_parse(handler, Oj.dump(payload, mode: :compat))

    expect(processor).to have_received(:handle_section).with('counts', hash_including('places' => 2))
    expect(processor).to have_received(:handle_section).with('settings', hash_including('theme' => 'dark'))
    expect(processor).to have_received(:handle_section).with('areas', [hash_including('name' => 'Home')])

    expect(processor).to have_received(:handle_stream_value).with('places', hash_including('name' => 'Cafe'))
    expect(processor).to have_received(:handle_stream_value).with('places', hash_including('name' => 'Library'))
    expect(processor).to have_received(:handle_stream_value).with('visits', hash_including('name' => 'Morning Coffee'))
    expect(processor).to have_received(:handle_stream_value).with('points', hash_including('timestamp' => 1))

    expect(processor).to have_received(:finish_stream).with('places')
    expect(processor).to have_received(:finish_stream).with('visits')
    expect(processor).to have_received(:finish_stream).with('points')

    expect(processor).not_to have_received(:handle_section).with('places', anything)
    expect(processor).not_to have_received(:handle_section).with('visits', anything)
    expect(processor).not_to have_received(:handle_section).with('points', anything)
  end
end
