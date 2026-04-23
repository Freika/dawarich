# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Traccar::Params do
  subject(:params) { described_class.new(input).call }

  describe '#call' do
    let(:input) do
      {
        device_id: 'iphone-frey',
        location: {
          timestamp: '2026-04-23T12:34:56Z',
          latitude: 52.52,
          longitude: 13.405,
          accuracy: 5,
          speed: 1.4,
          heading: 90,
          altitude: 42,
          is_moving: true,
          odometer: 1200,
          event: 'motionchange'
        },
        battery: {
          level: 0.85,
          is_charging: true
        },
        activity: {
          type: 'walking'
        }
      }
    end

    it 'maps latitude/longitude into a PostGIS POINT' do
      expect(params[:lonlat]).to eq('POINT(13.405 52.52)')
    end

    it 'maps device_id to tracker_id' do
      expect(params[:tracker_id]).to eq('iphone-frey')
    end

    it 'parses ISO 8601 timestamp to unix seconds' do
      expect(params[:timestamp]).to eq(DateTime.parse('2026-04-23T12:34:56Z').to_i)
    end

    it 'passes accuracy through' do
      expect(params[:accuracy]).to eq(5)
    end

    it 'passes altitude through' do
      expect(params[:altitude]).to eq(42)
    end

    it 'stores velocity as string (m/s, matching Dawarich convention)' do
      expect(params[:velocity]).to eq('1.4')
    end

    it 'converts battery level 0-1 to integer 0-100' do
      expect(params[:battery]).to eq(85)
    end

    it 'maps is_charging=true to charging' do
      expect(params[:battery_status]).to eq('charging')
    end

    context 'when is_charging is false' do
      before { input[:battery][:is_charging] = false }

      it 'maps to unplugged' do
        expect(params[:battery_status]).to eq('unplugged')
      end
    end

    context 'when battery block is missing' do
      before { input.delete(:battery) }

      it 'returns nil battery and unknown status' do
        expect(params[:battery]).to be_nil
        expect(params[:battery_status]).to eq('unknown')
      end
    end

    it 'extracts activity.type into motion_data' do
      expect(params[:motion_data]).to include('activity' => 'walking')
    end

    it 'includes is_moving and event in motion_data when present' do
      expect(params[:motion_data]).to include('is_moving' => true, 'event' => 'motionchange')
    end

    it 'stores the full raw payload' do
      expect(params[:raw_data]).to be_a(Hash)
      expect(params[:raw_data]['device_id']).to eq('iphone-frey')
    end

    context 'when location is missing' do
      let(:input) { { device_id: 'x' } }

      it 'returns nil' do
        expect(params).to be_nil
      end
    end

    context 'when latitude is missing' do
      before { input[:location].delete(:latitude) }

      it 'returns nil' do
        expect(params).to be_nil
      end
    end

    context 'when timestamp is missing' do
      before { input[:location].delete(:timestamp) }

      it 'returns nil' do
        expect(params).to be_nil
      end
    end

    context 'with string keys (e.g., from controller params)' do
      let(:input) do
        {
          'device_id' => 'x',
          'location' => {
            'timestamp' => '2026-04-23T12:00:00Z',
            'latitude' => 1.0,
            'longitude' => 2.0
          }
        }
      end

      it 'normalizes keys and produces a valid payload' do
        expect(params[:lonlat]).to eq('POINT(2.0 1.0)')
        expect(params[:tracker_id]).to eq('x')
      end
    end
  end
end
