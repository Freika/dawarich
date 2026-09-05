# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::Parsers::Registry do
  it 'lists registered formats and accepted extensions' do
    expect(described_class.formats).to include(
      hash_including(key: 'airtrail_json'),
      hash_including(key: 'flightdiary_csv')
    )
    expect(described_class.accepted_extensions).to include('.json', '.csv')
    expect(described_class.accept_attribute).to include('.csv')
  end

  it 'detects and parses AirTrail export JSON content' do
    content = file_fixture('air_trail/export_v3.json').read

    flights = described_class.parse(content)

    expect(flights.size).to eq(1)
    expect(flights.first[:external_id]).to be_present
    expect(flights.first[:from_code]).to eq('EDDB')
  end

  it 'detects and parses FlightDiary CSV content' do
    content = file_fixture('flight_diary/export.csv').read

    flights = described_class.parse(content)

    expect(flights.size).to eq(4)
    expect(flights.first[:from_code]).to eq('LFPG')
  end

  it 'parses with an explicit format key' do
    content = file_fixture('air_trail/export_v3.json').read

    flights = described_class.parse(content, format: :airtrail_json)

    expect(flights.size).to eq(1)
  end

  it 'raises for unsupported formats' do
    expect { described_class.detect_and_parse({ 'records' => [] }) }
      .to raise_error(Flights::Parsers::Error, /Unsupported flight file format/)
  end

  it 'raises for invalid JSON when format is explicit' do
    expect { described_class.parse('not json', format: :airtrail_json) }
      .to raise_error(Flights::Parsers::Error, /Invalid JSON/)
  end

  it 'accepts csv filenames' do
    expect(described_class.supported_format?(filename: 'flights.csv', content_type: 'text/csv')).to be(true)
  end
end
