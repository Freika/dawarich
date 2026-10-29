# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timezones::LoadBoundaries do
  let(:fixture) { Rails.root.join('spec/fixtures/files/timezones/kansas.geojson.gz') }

  def zone_at(longitude, latitude)
    Timezone.where('ST_Covers(geom, ST_SetSRID(ST_MakePoint(?, ?), 4326))', longitude, latitude).pick(:tzid)
  end

  it 'loads every zone of the file' do
    described_class.new(fixture).call

    expect(zone_at(-97.34, 37.69)).to eq('America/Chicago')
    expect(zone_at(-101.71, 39.35)).to eq('America/Denver')
  end

  it 'replaces the previous load instead of duplicating it' do
    described_class.new(fixture).call

    expect { described_class.new(fixture).call }.not_to(change { Timezone.count })
  end

  it 'loads the bundled boundaries' do
    described_class.new.call

    expect(zone_at(-97.34, 37.69)).to eq('America/Chicago') # Wichita, Kansas
    expect(zone_at(-101.71, 39.35)).to eq('America/Denver') # Goodland, Kansas
    expect(zone_at(13.40, 52.52)).to eq('Europe/Berlin')
    expect(zone_at(-40.0, 40.0)).to be_present # mid-Atlantic, covered by the ocean zones
  end
end
