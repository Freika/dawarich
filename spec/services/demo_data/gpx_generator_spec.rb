# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DemoData::GpxGenerator do
  subject(:generator) { described_class.new(base_time: base_time) }

  let(:base_time) { Time.zone.parse('2026-03-26 18:00:00') }

  describe '#call' do
    let(:result) { generator.call }
    let(:data) { Oj.load(result) }
    let(:features) { data['features'] }

    it 'returns valid GeoJSON FeatureCollection' do
      expect(data['type']).to eq('FeatureCollection')
      expect(features).to be_an(Array)
      expect(features).not_to be_empty
    end

    it 'generates approximately 1000 points' do
      expect(features.length).to be_between(900, 1200)
    end

    it 'generates points with Berlin coordinates' do
      latitudes = features.map { |f| f['properties']['latitude'].to_f }
      longitudes = features.map { |f| f['properties']['longitude'].to_f }

      expect(latitudes).to all(be_between(52.0, 53.0))
      expect(longitudes).to all(be_between(12.5, 14.0))
    end

    it 'shifts timestamps so the last point matches base_time' do
      timestamps = features.map { |f| f['properties']['timestamp'] }
      last_timestamp = Time.zone.at(timestamps.max)

      expect(last_timestamp).to be_within(1.second).of(base_time)
    end

    it 'preserves relative time ordering' do
      timestamps = features.map { |f| f['properties']['timestamp'] }
      expect(timestamps).to eq(timestamps.sort)
    end

    it 'contains no negative velocity points' do
      velocities = features.map { |f| f['properties']['velocity'] }.compact
      negative = velocities.select { |v| v.to_f.negative? }

      expect(negative).to be_empty
    end
  end
end
