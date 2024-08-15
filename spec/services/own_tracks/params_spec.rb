# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::Params do
  describe '#call' do
    subject(:params) { described_class.new(raw_point_params).call }

    let(:file_path) { 'spec/fixtures/files/owntracks/export.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:user) { json.keys.first }
    let(:topic) { json[user].keys.first }
    let(:raw_point_params) { json[user][topic].first }

    let(:expected_json) do
      {
        latitude: 40.7128,
        longitude: -74.006,
        battery_status: 'charging',
        battery: 85,
        ping: nil,
        altitude: 41,
        accuracy: 8,
        vertical_accuracy: 3,
        velocity: nil,
        connection: 'wifi',
        ssid: 'Home Wifi',
        bssid: 'b0:f2:8:45:94:33',
        trigger: 'background_event',
        tracker_id: 'RO',
        timestamp: 1_706_965_203,
        inrids: ['5f1d1b'],
        in_regions: ['home'],
        topic: 'owntracks/test/iPhone 12 Pro',
        raw_data: {
          'batt' => 85,
          'lon' => -74.006,
          'acc' => 8,
          'bs' => 2,
          'inrids' => ['5f1d1b'],
          'BSSID' => 'b0:f2:8:45:94:33',
          'SSID' => 'Home Wifi',
          'vac' => 3,
          'inregions' => ['home'],
          'lat' => 40.7128,
          'topic' => 'owntracks/test/iPhone 12 Pro',
          't' => 'p',
          'conn' => 'w',
          'm' => 1,
          'tst' => 1_706_965_203,
          'alt' => 41,
          '_type' => 'location',
          'tid' => 'RO',
          '_http' => true,
          'ghash' => 'u33d773',
          'isorcv' => '2024-02-03T13:00:03Z',
          'isotst' => '2024-02-03T13:00:03Z',
          'disptst' => '2024-02-03 13:00:03'
        }
      }
    end

    it 'returns parsed params' do
      expect(params).to eq(expected_json)
    end

    context 'when battery status is unplugged' do
      let(:raw_point_params) { super().merge(bs: 1) }

      it 'returns parsed params' do
        expect(params[:battery_status]).to eq('unplugged')
      end
    end

    context 'when battery status is charging' do
      let(:raw_point_params) { super().merge(bs: 2) }

      it 'returns parsed params' do
        expect(params[:battery_status]).to eq('charging')
      end
    end

    context 'when battery status is full' do
      let(:raw_point_params) { super().merge(bs: 3) }

      it 'returns parsed params' do
        expect(params[:battery_status]).to eq('full')
      end
    end

    context 'when trigger is background_event' do
      let(:raw_point_params) { super().merge(m: 'p') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('background_event')
      end
    end

    context 'when trigger is circular_region_event' do
      let(:raw_point_params) { super().merge(t: 'c') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('circular_region_event')
      end
    end

    context 'when trigger is beacon_event' do
      let(:raw_point_params) { super().merge(t: 'b') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('beacon_event')
      end
    end

    context 'when trigger is report_location_message_event' do
      let(:raw_point_params) { super().merge(t: 'r') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('report_location_message_event')
      end
    end

    context 'when trigger is manual_event' do
      let(:raw_point_params) { super().merge(t: 'u') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('manual_event')
      end
    end

    context 'when trigger is timer_based_event' do
      let(:raw_point_params) { super().merge(t: 't') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('timer_based_event')
      end
    end

    context 'when trigger is settings_monitoring_event' do
      let(:raw_point_params) { super().merge(t: 'v') }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('settings_monitoring_event')
      end
    end

    context 'when connection is mobile' do
      let(:raw_point_params) { super().merge(conn: 'm') }

      it 'returns parsed params' do
        expect(params[:connection]).to eq('mobile')
      end
    end

    context 'when connection is wifi' do
      let(:raw_point_params) { super().merge(conn: 'w') }

      it 'returns parsed params' do
        expect(params[:connection]).to eq('wifi')
      end
    end

    context 'when connection is offline' do
      let(:raw_point_params) { super().merge(conn: 'o') }

      it 'returns parsed params' do
        expect(params[:connection]).to eq('offline')
      end
    end

    context 'when connection is unknown' do
      let(:raw_point_params) { super().merge(conn: 'unknown') }

      it 'returns parsed params' do
        expect(params[:connection]).to eq('unknown')
      end
    end

    context 'when battery status is unknown' do
      let(:raw_point_params) { super().merge(bs: 'unknown') }

      it 'returns parsed params' do
        expect(params[:battery_status]).to eq('unknown')
      end
    end

    context 'when trigger is unknown' do
      before { raw_point_params[:t] = 'unknown' }

      it 'returns parsed params' do
        expect(params[:trigger]).to eq('unknown')
      end
    end
  end
end
