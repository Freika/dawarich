# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::ImportFromJson do
  let(:user) { create(:user) }
  let(:json_string) { file_fixture('air_trail/export_v3.json').read }

  it 'imports flights from an AirTrail export file' do
    result = described_class.new(user, json_string).call

    expect(user.flights.count).to eq(1)
    expect(user.flights.first.from_code).to eq('EDDB')
    expect(user.flights.first.flight_number).to eq('AF1235')
    expect(result[:created]).to eq(1)
    expect(user.reload.settings['airtrail_last_imported_at']).to be_present
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
    expect { described_class.new(user, 'not json').call }
      .to raise_error(Flights::Parsers::Error, /Invalid JSON/)
  end
end
