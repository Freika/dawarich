# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::DisplayPath do
  let(:track) do
    create(:track,
           original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
           matched_path: 'MULTILINESTRING((13.4 52.5, 13.405 52.505, 13.41 52.51))',
           map_matching_status: :matched,
           map_matching_input_digest: 'current')
  end

  before do
    allow(DawarichSettings).to receive(:map_matching_enabled?).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:map_matching_shadow_mode).and_return(false)
  end

  it 'selects matched geometry only for the display variant' do
    expect(described_class.for(track, variant: 'original')).to eq(track.original_path)
    expect(described_class.for(track, variant: 'display')).to eq(track.matched_path)
    expect(described_class.for(track, variant: 'matched')).to eq(track.matched_path)
  end

  it 'returns original geometry when shadow mode is enabled' do
    allow(Flipper).to receive(:enabled?).with(:map_matching_shadow_mode).and_return(true)

    expect(described_class.for(track, variant: 'display')).to eq(track.original_path)
    expect(described_class.for(track, variant: 'matched')).to be_nil
  end

  it 'returns original geometry for pending or stale-looking results' do
    track.update!(map_matching_status: :pending)
    expect(described_class.for(track, variant: 'display')).to eq(track.original_path)

    track.update!(map_matching_status: :matched, map_matching_input_digest: nil)
    expect(described_class.for(track, variant: 'display')).to eq(track.original_path)
  end
end
