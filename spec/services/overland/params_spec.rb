# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Overland::Params do
  describe '#call' do
    # This file contains one valid point and one invalid point w/out coordinates
    let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }

    let(:expected_json) do
      {
        lonlat: 'POINT(-122.030581 37.3318)',
        battery_status: 'charging',
        battery: 89,
        altitude: 0,
        accuracy: 30,
        vertical_accuracy: -1,
        velocity: 4,
        ssid: 'launchpad',
        tracker_id: '',
        timestamp: DateTime.parse('2015-10-01T08:00:00-0700'),
        motion_data: {
          motion: ['driving', 'stationary'],
          activity: 'other_navigation'
        },
        raw_data: {}
      }
    end

    subject(:params) { described_class.new(json).call }

    it 'returns a hash with the correct keys' do
      expect(params[0].keys).to match_array(
        %i[
          battery_status
          battery
          altitude
          accuracy
          vertical_accuracy
          velocity
          ssid
          tracker_id
          timestamp
          motion_data
          raw_data
          lonlat
        ]
      )
    end

    it 'returns a hash with the correct values' do
      expect(params[0]).to eq(expected_json)
    end

    it 'returns the correct number of points' do
      expect(params.size).to eq(1)
    end
  end
end
