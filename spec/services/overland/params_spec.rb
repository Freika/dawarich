require 'rails_helper'

RSpec.describe Overland::Params do
  describe '#call' do
    let(:file_path) { 'spec/fixtures/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }

    let(:expected_json) do
      {
        latitude: 37.3318,
        longitude: -122.030581,
        battery_status: 'charging',
        battery: 89,
        altitude: 0,
        accuracy: 30,
        vertical_accuracy: -1,
        velocity: 4,
        ssid: 'launchpad',
        tracker_id: '',
        timestamp: DateTime.parse('2015-10-01T08:00:00-0700'),
        raw_data: json['locations'][0]
      }
    end

    subject(:params) { described_class.new(json).call }

    it 'returns a hash with the correct keys' do
      expect(params[0].keys).to match_array(
        %i[
          latitude
          longitude
          battery_status
          battery
          altitude
          accuracy
          vertical_accuracy
          velocity
          ssid
          tracker_id
          timestamp
          raw_data
        ]
      )
    end

    it 'returns a hash with the correct values' do
      expect(params[0]).to eq(expected_json)
    end
  end
end

