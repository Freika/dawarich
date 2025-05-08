# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::Params do
  describe '#call' do
    let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
    let(:file) { File.read(file_path) }
    let(:json) { JSON.parse(file) }
    let(:params) { described_class.new(json) }

    subject { params.call }

    it 'returns an array of points' do
      expect(subject).to be_an_instance_of(Array)
      expect(subject.first).to be_an_instance_of(Hash)
    end

    it 'returns the correct data for each point' do
      expect(subject.first).to eq(
        lonlat: 'POINT(0.1 0.1)',
        battery_status: nil,
        battery: nil,
        timestamp: Time.zone.at(1_609_459_201),
        altitude: 1,
        velocity: 1.5,
        tracker_id: nil,
        ssid: nil,
        accuracy: 1,
        vertical_accuracy: 1,
        raw_data: {
          'type' => 'Feature',
          'geometry' => {
            'type' => 'Point',
            'coordinates' => [
              '0.1',
              '0.1'
            ]
          },
          'properties' => {
            'battery_status' => 'unplugged',
            'ping' => 'MyString',
            'battery' => 1,
            'tracker_id' => 'MyString',
            'topic' => 'MyString',
            'altitude' => 1,
            'longitude' => '0.1',
            'velocity' => 1.5,
            'trigger' => 'background_event',
            'bssid' => 'MyString',
            'ssid' => 'MyString',
            'connection' => 'wifi',
            'vertical_accuracy' => 1,
            'accuracy' => 1,
            'timestamp' => 1_609_459_201,
            'latitude' => '0.1',
            'mode' => 1,
            'inrids' => [],
            'in_regions' => [],
            'raw_data' => '',
            'city' => nil,
            'country' => nil,
            'geodata' => {}
          }
        }
      )
    end

    context 'when the json is exported from GPSLogger' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/gpslogger_example.json') }

      it 'returns the correct data for each point' do
        expect(subject.first).to eq(
          lonlat: 'POINT(106.64234449272531 10.758321212464024)',
          battery_status: nil,
          battery: nil,
          timestamp: Time.parse('2024-11-03T16:30:11.331+07:00').to_i,
          altitude: 17.634344400269068,
          velocity: 1.2,
          tracker_id: nil,
          ssid: nil,
          accuracy: 4.7551565,
          vertical_accuracy: nil,
          raw_data: {
            'geometry' => {
              'coordinates' => [
                106.64234449272531,
                10.758321212464024
              ],
              'type' => 'Point'
            },
            'properties' => {
              'accuracy' => 4.7551565,
              'altitude' => 17.634344400269068,
              'provider' => 'gps',
              'speed' => 1.2,
              'time' => '2024-11-03T16:30:11.331+07:00',
              'time_long' => 1_730_626_211_331
            },
            'type' => 'Feature'
          }
        )
      end
    end
  end
end
