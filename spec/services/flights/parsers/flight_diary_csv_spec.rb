# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::Parsers::FlightDiaryCsv do
  let(:csv) { file_fixture('flight_diary/export.csv').read }

  it 'exposes format metadata' do
    expect(described_class.key).to eq(:flightdiary_csv)
    expect(described_class.label).to include('FlightDiary')
    expect(described_class.extensions).to include('.csv')
  end

  it 'parses FlightDiary CSV into Flight attributes with coords' do
    flights = described_class.call(described_class.decode(csv))

    expect(flights.size).to eq(4)
    first = flights.first
    expect(first[:from_code]).to eq('LFPG')
    expect(first[:to_code]).to eq('LFBO')
    expect(first[:flight_number]).to eq('AF6116')
    expect(first[:airline_name]).to eq('Air France')
    expect(first[:airline_iata]).to eq('AF')
    expect(first[:from_lat]).to be_present
    expect(first[:to_lat]).to be_present
    expect(first[:external_id]).to be >= Flights::ExternalId::FLIGHTDIARY_FILE_ID_OFFSET
    expect(first[:seat_class]).to eq('economy')
  end

  it 'handles overnight arrivals' do
    flights = described_class.call(described_class.decode(csv))
    overnight = flights.find { |f| f[:flight_number] == 'AI314M' }

    expect(overnight[:departure_time].to_date).to eq(Date.new(2006, 6, 9))
    expect(overnight[:arrival_time].to_date).to eq(Date.new(2006, 6, 10))
  end

  it 'maps business class and missing flight numbers' do
    flights = described_class.call(described_class.decode(csv))

    business = flights.find { |f| f[:flight_number] == 'AF6114' }
    expect(business[:seat_class]).to eq('business')

    no_number = flights.find { |f| f[:flight_date] == Date.new(2004, 4, 8) }
    expect(no_number[:flight_number]).to be_nil
    expect(no_number[:from_code]).to eq('LFPG')
  end

  it 'assigns stable external ids' do
    data = described_class.decode(csv)
    id1 = described_class.call(data).first[:external_id]
    id2 = described_class.call(data).first[:external_id]

    expect(id1).to eq(id2)
  end

  it 'raises when no flights are present' do
    expect { described_class.call([]) }
      .to raise_error(Flights::Parsers::Error, /No flights found/)
  end

  it 'ignores a leading blank line before the header row' do
    content = "\n#{csv}"

    flights = Flights::Parsers::Registry.parse(content)

    expect(flights.size).to eq(4)
    expect(flights.first[:from_code]).to eq('LFPG')
  end
end
