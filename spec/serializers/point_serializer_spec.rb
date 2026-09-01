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
        point.update_columns(source_id: source.id)
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
    # The full payload key set is a contract: the scratch map reads
    # country_name, mobile clients decode velocity as a string, and the
    # combo keys flow from the dimension.
    let(:expected_json) do
      {
        'battery' => point.battery,
        'timestamp' => point.timestamp,
        'altitude' => point.altitude,
        'velocity' => point.velocity&.to_s,
        'accuracy' => point.accuracy,
        'vertical_accuracy' => point.vertical_accuracy,
        'course' => point.course,
        'course_accuracy' => point.course_accuracy,
        'city' => point.city,
        'geodata' => point.geodata,
        'track_id' => point.track_id,
        'raw_data_archived' => point.raw_data_archived,
        'raw_data_archive_id' => point.raw_data_archive_id,
        'motion_data' => point.motion_data,
        'anomaly' => point.anomaly,
        'longitude' => point.lon.to_s,
        'latitude' => point.lat.to_s,
        'country_name' => point.country_name,
        'tracker_id' => point.tracker_id,
        'topic' => point.topic,
        'ssid' => point.ssid,
        'bssid' => point.bssid,
        'connection' => point.connection,
        'trigger' => point.trigger,
        'battery_status' => point.battery_status,
        'inrids' => point.inrids,
        'in_regions' => point.in_regions
      }
    end

    it 'returns JSON with correct attributes' do
      expect(JSON.parse(serializer.to_json)).to eq(expected_json)
    end

    it 'pins the exact payload key set' do
      expect(serializer.keys).to match_array(expected_json.keys)
    end
  end
end
