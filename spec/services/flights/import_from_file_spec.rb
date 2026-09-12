# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::ImportFromFile do
  let(:user) { create(:user) }
  let(:json_string) { file_fixture('air_trail/export_v3.json').read }

  it 'imports flights from an AirTrail export file' do
    result = described_class.new(user, json_string).call

    expect(user.flights.count).to eq(1)
    expect(user.flights.first.from_code).to eq('EDDB')
    expect(user.flights.first.flight_number).to eq('AF1235')
    expect(result[:created]).to eq(1)
    expect(user.reload.settings['flights_last_imported_at']).to be_present
  end

  it 'is idempotent on re-import' do
    described_class.new(user, json_string).call
    result = described_class.new(user, json_string).call

    expect(user.flights.count).to eq(1)
    expect(result).to include(created: 0, updated: 1, deleted: 0)
  end

  it 'does not delete flights missing from the file' do
    create(:flight, user: user, external_id: 99)

    described_class.new(user, json_string).call

    expect(user.flights.pluck(:external_id).size).to eq(2)
  end

  it 'raises on invalid JSON' do
    expect { described_class.new(user, 'not json', format: :airtrail_json).call }
      .to raise_error(Flights::Parsers::Error, /Invalid JSON/)
  end

  it 'accepts an explicit format' do
    result = described_class.new(user, json_string, format: :airtrail_json).call

    expect(result[:created]).to eq(1)
  end

  it 'imports flights from a FlightDiary CSV file' do
    csv = file_fixture('flight_diary/export.csv').read

    result = described_class.new(user, csv).call

    expect(result[:created]).to eq(4)
    expect(user.flights.find_by(flight_number: 'AF6116').from_code).to eq('LFPG')
    expect(user.flights.find_by(flight_number: 'AF6116').from_lat).to be_present
  end

  it 'is idempotent for FlightDiary CSV re-import' do
    csv = file_fixture('flight_diary/export.csv').read

    described_class.new(user, csv).call
    result = described_class.new(user, csv).call

    expect(user.flights.count).to eq(4)
    expect(result).to include(created: 0, updated: 4, deleted: 0)
  end
end
