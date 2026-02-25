# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::GeojsonSerializer do
  let(:track) do
    create(:track,
           start_at: Time.zone.parse('2024-01-01 10:00'),
           end_at: Time.zone.parse('2024-01-01 11:00'),
           distance: 1234.56,
           avg_speed: 42.5,
           duration: 3600)
  end

  describe '#call' do
    it 'returns a FeatureCollection structure' do
      result = described_class.new([track]).call

      expect(result[:type]).to eq('FeatureCollection')
      expect(result[:features].length).to eq(1)
    end

    it 'includes geometry and track properties' do
      feature = described_class.new([track]).call[:features].first

      expect(feature[:geometry][:type]).to eq('LineString')
      expect(feature[:properties]).to include(
        id: track.id,
        color: '#6366F1',
        start_at: track.start_at.iso8601,
        end_at: track.end_at.iso8601,
        distance: track.distance.to_i,
        avg_speed: track.avg_speed.to_f,
        duration: track.duration
      )
    end
  end
end
