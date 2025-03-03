# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Params do
  describe '#call' do
    let(:user) { create(:user) }
    let(:file_path) { 'spec/fixtures/files/points/geojson_example.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:expected_json) do
      {
        lonlat:             'POINT(-122.40530871 37.74430413)',
        battery_status:     nil,
        battery:            nil,
        timestamp:          DateTime.parse('2025-01-17T21:03:01Z'),
        altitude:           0,
        tracker_id:         '8D5D4197-245B-4619-A88B-2049100ADE46',
        velocity:           92.088,
        ssid:               nil,
        accuracy:           5,
        vertical_accuracy:  -1,
        course_accuracy:    0,
        course:             27.07,
        raw_data:           {
          type:               'Feature',
          geometry:           {
            type:             'Point',
            coordinates:      [-122.40530871, 37.74430413]
          },
          properties:         {
            horizontal_accuracy: 5,
            track_id:            '799F32F5-89BB-45FB-A639-098B1B95B09F',
            speed_accuracy:      0,
            vertical_accuracy:   -1,
            course_accuracy:    0,
            altitude:           0,
            speed:              92.088,
            course:             27.07,
            timestamp:          '2025-01-17T21:03:01Z',
            device_id:          '8D5D4197-245B-4619-A88B-2049100ADE46'
          }
        }.with_indifferent_access,
        user_id:            user.id
      }
    end

    subject(:params) { described_class.new(json, user.id).call }

    it 'returns an array of points' do
      expect(params).to be_an(Array)
      expect(params.first).to eq(expected_json)
    end

    it 'returns the correct number of points' do
      expect(params.size).to eq(6)
    end

    it 'returns correct keys' do
      expect(params.first.keys).to eq(expected_json.keys)
    end

    it 'returns the correct values' do
      expect(params.first).to eq(expected_json)
    end
  end
end
