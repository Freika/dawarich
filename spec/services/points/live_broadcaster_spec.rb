# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::LiveBroadcaster do
  let(:user) { create(:user) }

  let(:upserted_results) do
    [
      { 'id' => 1, 'timestamp' => 1_700_000_000, 'latitude' => 52.52, 'longitude' => 13.405 }
    ]
  end

  let(:payloads) do
    [
      { timestamp: 1_700_000_000, battery: 85, altitude: 100, velocity: '5.0' }
    ]
  end

  describe '#call' do
    context 'when live_map_enabled is true' do
      before do
        user.settings['live_map_enabled'] = true
        user.save!
      end

      it 'broadcasts point data to PointsChannel' do
        expect(PointsChannel).to receive(:broadcast_to).with(
          user,
          [52.52, 13.405, '85', '100', '1700000000', '5.0', '1', '']
        )

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'when live_map_enabled is false' do
      before do
        user.settings['live_map_enabled'] = false
        user.save!
      end

      it 'does not broadcast' do
        expect(PointsChannel).not_to receive(:broadcast_to)

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'when upserted_results is empty' do
      it 'does not broadcast' do
        expect(PointsChannel).not_to receive(:broadcast_to)

        described_class.new(user.id, [], payloads).call
      end
    end

    context 'when user does not exist' do
      it 'does not broadcast' do
        expect(PointsChannel).not_to receive(:broadcast_to)

        described_class.new(-1, upserted_results, payloads).call
      end
    end

    context 'with multiple points' do
      let(:upserted_results) do
        [
          { 'id' => 1, 'timestamp' => 1_700_000_000, 'latitude' => 52.52, 'longitude' => 13.405 },
          { 'id' => 2, 'timestamp' => 1_700_000_060, 'latitude' => 52.53, 'longitude' => 13.41 }
        ]
      end

      let(:payloads) do
        [
          { timestamp: 1_700_000_000, battery: 85, altitude: 100, velocity: '5.0' },
          { timestamp: 1_700_000_060, battery: 80, altitude: 110, velocity: '10.0' }
        ]
      end

      before do
        user.settings['live_map_enabled'] = true
        user.save!
      end

      it 'broadcasts each point' do
        expect(PointsChannel).to receive(:broadcast_to).twice

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'when payload has no matching timestamp' do
      before do
        user.settings['live_map_enabled'] = true
        user.save!
      end

      let(:payloads) { [{ timestamp: 9_999_999_999, battery: 50, altitude: 0, velocity: '0' }] }

      it 'broadcasts with empty strings for missing fields' do
        expect(PointsChannel).to receive(:broadcast_to).with(
          user,
          [52.52, 13.405, '', '', '1700000000', '', '1', '']
        )

        described_class.new(user.id, upserted_results, payloads).call
      end
    end
  end
end
