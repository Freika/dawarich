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
        motion_data:        {},
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
            course_accuracy:     0,
            altitude:            0,
            speed:               92.088,
            course:              27.07,
            timestamp:           '2025-01-17T21:03:01Z',
            device_id:           '8D5D4197-245B-4619-A88B-2049100ADE46'
          }
        }.with_indifferent_access,
        user_id:            user.id,
        altitude_decimal:   0
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

  describe 'course sanitization' do
    let(:user) { create(:user) }

    def build_payload(course:, course_accuracy: 0)
      {
        locations: [
          {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [13.404954, 52.520008] },
            properties: {
              timestamp: '2026-06-13T09:03:57Z',
              course: course,
              course_accuracy: course_accuracy
            }
          }
        ]
      }
    end

    it 'nils out course whose absolute value exceeds the numeric(8,5) limit' do
      result = described_class.new(build_payload(course: 1000.0), user.id).call

      expect(result.first[:course]).to be_nil
    end

    it 'nils out course_accuracy whose absolute value exceeds the numeric(8,5) limit' do
      result = described_class.new(build_payload(course: 27.07, course_accuracy: 9999.0), user.id).call

      expect(result.first[:course_accuracy]).to be_nil
    end

    it 'keeps valid course and course_accuracy values' do
      result = described_class.new(build_payload(course: 359.99, course_accuracy: 12.5), user.id).call

      expect(result.first[:course]).to eq(359.99)
      expect(result.first[:course_accuracy]).to eq(12.5)
    end
  end

  describe 'Null Island filtering' do
    let(:user) { create(:user) }
    let(:params) do
      {
        locations: [
          {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [0.0, 0.0] },
            properties: { timestamp: '2025-01-17T21:03:01Z' }
          },
          {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [13.5, 52.4] },
            properties: { timestamp: '2025-01-17T21:04:01Z' }
          }
        ]
      }
    end

    it 'drops locations at exactly (0,0) and keeps the rest' do
      result = described_class.new(params, user.id).call

      expect(result.size).to eq(1)
      expect(result.first[:lonlat]).to eq('POINT(13.5 52.4)')
    end
  end
end
