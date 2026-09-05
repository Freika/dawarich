# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::AirportLookup do
  it 'resolves a well-known ICAO code' do
    result = described_class.call(icao: 'LFPG')

    expect(result).to include(
      icao: 'LFPG',
      iata: 'CDG'
    )
    expect(result[:lat]).to be_a(Float)
    expect(result[:lon]).to be_a(Float)
  end

  it 'falls back to IATA when ICAO is missing' do
    result = described_class.call(iata: 'CDG')

    expect(result[:icao]).to eq('LFPG')
  end

  it 'returns nil for unknown codes' do
    expect(described_class.call(icao: 'ZZZZ')).to be_nil
  end
end
