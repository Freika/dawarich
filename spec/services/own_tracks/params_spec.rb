# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::Params do
  describe '#call' do
    subject(:params) { described_class.new(raw_point_params).call }

    let(:file_path) { 'spec/fixtures/files/owntracks/2024-03.rec' }
    let(:file) { File.read(file_path) }
    let(:json) { OwnTracks::RecParser.new(file).call }
    let(:raw_point_params) { json.first }

    let(:expected_json) do
      {
        latitude: 52.225,
        longitude: 13.332,
        battery: 94,
        ping: 100.266,
        altitude: 36,
        accuracy: 10,
        vertical_accuracy: 4,
        velocity: '1.4',
        ssid: 'Home Wifi',
        bssid: 'b0:f2:8:45:94:33',
        tracker_id: 'RO',
        timestamp: 1_709_283_789,
        inrids: ['5f1d1b'],
        in_regions: ['home'],
        topic: 'owntracks/test/iPhone 12 Pro',
        battery_status: 'charging',
        connection: 'wifi',
        trigger: 'background_event',
        raw_data:   { 'bs' => 2,
          'p' => 100.266,
          'batt' => 94,
          '_type' => 'location',
          'tid' => 'RO',
          'topic' => 'owntracks/test/iPhone 12 Pro',
          'alt' => 36,
          'lon' => 13.332,
          'vel' => 5,
          't' => 'p',
          'BSSID' => 'b0:f2:8:45:94:33',
          'SSID' => 'Home Wifi',
          'conn' => 'w',
          'vac' => 4,
          'acc' => 10,
          'tst' => 1_709_283_789,
          'lat' => 52.225,
          'm' => 1,
          'inrids' => ['5f1d1b'],
          'inregions' => ['home'],
          '_http' => true }
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
