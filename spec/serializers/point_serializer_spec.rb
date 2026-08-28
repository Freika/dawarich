# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }

    context 'when the point is stamped with a dimension row' do
      before do
        source = PointSource.create!(digest: 'a' * 32, tracker_id: 'dimension-device',
                                     topic: 'owntracks/dim', battery_status: 'unplugged')
        point.update_columns(source_id: source.id, tracker_id: 'legacy-device',
                             topic: 'owntracks/legacy', battery_status: 0)
        point.reload
      end

      it 'emits the device combo from the dimension, under the same keys' do
        expect(serializer['tracker_id']).to eq('dimension-device')
        expect(serializer['topic']).to eq('owntracks/dim')
        expect(serializer['battery_status']).to eq('unplugged')
      end

      it 'keeps the payload key order unchanged' do
        expect(serializer.keys).to eq(described_class.new(create(:point)).call.keys)
      end
    end
    let(:expected_json) do
      {
        'battery_status' => point.battery_status,
        'ping' => point.ping,
        'battery' => point.battery,
        'tracker_id' => point.tracker_id,
        'topic' => point.topic,
        'altitude' => point.altitude.to_s,
        'longitude' => point.lon.to_s,
        'velocity' => point.velocity,
        'trigger' => point.trigger,
        'bssid' => point.bssid,
        'ssid' => point.ssid,
        'connection' => point.connection,
        'vertical_accuracy' => point.vertical_accuracy,
        'accuracy' => point.accuracy,
        'timestamp' => point.timestamp,
        'latitude' => point.lat.to_s,
        'mode' => point.mode,
        'inrids' => point.inrids,
        'in_regions' => point.in_regions,
        'city' => point.city,
        'country' => point.read_attribute(:country),
        'geodata' => point.geodata,
        'course' => point.course,
        'course_accuracy' => point.course_accuracy,
        'external_track_id' => point.external_track_id,
        'track_id' => point.track_id,
        'country_name' => point.read_attribute(:country_name),
        'raw_data_archived' => point.raw_data_archived,
        'raw_data_archive_id' => point.raw_data_archive_id,
        'motion_data' => point.motion_data,
        'anomaly' => point.anomaly
      }
    end

    it 'returns JSON with correct attributes' do
      expect(JSON.parse(serializer.to_json)).to eq(expected_json)
    end
  end
end
