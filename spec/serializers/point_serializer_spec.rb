# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }
    let(:expected_json) do
      {
        'battery_status' => point.battery_status,
        'ping' => point.ping,
        'battery' => point.battery,
        'tracker_id' => point.tracker_id,
        'topic' => point.topic,
        'altitude' => point.altitude,
        'longitude' => point.lon,
        'velocity' => point.velocity,
        'trigger' => point.trigger,
        'bssid' => point.bssid,
        'ssid' => point.ssid,
        'connection' => point.connection,
        'vertical_accuracy' => point.vertical_accuracy,
        'accuracy' => point.accuracy,
        'timestamp' => point.timestamp,
        'latitude' => point.lat,
        'mode' => point.mode,
        'inrids' => point.inrids,
        'in_regions' => point.in_regions,
        'city' => point.city,
        'country' => point.country,
        'geodata' => point.geodata,
        'course' => point.course,
        'course_accuracy' => point.course_accuracy,
        'external_track_id' => point.external_track_id
      }
    end

    it 'returns JSON with correct attributes' do
      expect(serializer.to_json).to eq(expected_json.to_json)
    end
  end
end
