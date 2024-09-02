# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points, user_email).call }

    let(:user_email) { 'ab@cd.com' }
    let(:points) { create_list(:point, 2) }
    let(:expected_json) do
      {
        user_email => {
          'dawarich-export' => [
            {
              lat: points.first.latitude,
              lon: points.first.longitude,
              bs: 'u',
              batt: points.first.battery,
              p: points.first.ping,
              alt: points.first.altitude,
              acc: points.first.accuracy,
              vac: points.first.vertical_accuracy,
              vel: points.first.velocity,
              conn: 'w',
              SSID: points.first.ssid,
              BSSID: points.first.bssid,
              m: 'p',
              tid: points.first.tracker_id,
              tst: points.first.timestamp.to_i,
              inrids: points.first.inrids,
              inregions: points.first.in_regions,
              topic: points.first.topic,
              raw_data: points.first.raw_data
            },
            {
              lat: points.second.latitude,
              lon: points.second.longitude,
              bs: 'u',
              batt: points.second.battery,
              p: points.second.ping,
              alt: points.second.altitude,
              acc: points.second.accuracy,
              vac: points.second.vertical_accuracy,
              vel: points.second.velocity,
              conn: 'w',
              SSID: points.second.ssid,
              BSSID: points.second.bssid,
              m: 'p',
              tid: points.second.tracker_id,
              tst: points.second.timestamp.to_i,
              inrids: points.second.inrids,
              inregions: points.second.in_regions,
              topic: points.second.topic,
              raw_data: points.second.raw_data
            }
          ]
        }
      }.to_json
    end

    it 'returns JSON' do
      expect(serializer).to eq(expected_json)
    end
  end
end
