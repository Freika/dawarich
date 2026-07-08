# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::Parsers::Registry do
  it 'detects and parses AirTrail export JSON' do
    data = JSON.parse(file_fixture('air_trail/export_v3.json').read)

    flights = described_class.detect_and_parse(data)

    expect(flights.size).to eq(1)
    expect(flights.first['id']).to be_present
  end

  it 'raises for unsupported formats' do
    expect { described_class.detect_and_parse({ 'records' => [] }) }
      .to raise_error(Flights::Parsers::Error, /Unsupported flight JSON/)
  end
end
