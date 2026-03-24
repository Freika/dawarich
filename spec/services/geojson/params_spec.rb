# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::Params do
  describe 'field alias detection' do
    let(:fixture_path) { Rails.root.join('spec/fixtures/files/geojson/various_fields.geojson') }
    let(:json) { JSON.parse(File.read(fixture_path)) }
    let(:result) { described_class.new(json).call }

    it 'extracts points from all features' do
      expect(result.size).to eq(3)
    end

    it 'parses datetime alias for timestamp' do
      expect(result[0][:timestamp]).not_to be_nil
    end

    it 'parses when alias for timestamp' do
      expect(result[1][:timestamp]).not_to be_nil
    end

    it 'parses recorded_at alias for timestamp' do
      expect(result[2][:timestamp]).not_to be_nil
    end

    it 'parses vel alias for velocity' do
      expect(result[0][:velocity]).to eq(1.5)
    end

    it 'converts speed_kmh to m/s' do
      expect(result[1][:velocity]).to eq(1.5) # 5.4 / 3.6 = 1.5
    end

    it 'parses acc alias for accuracy' do
      expect(result[0][:accuracy]).to eq(8)
    end

    it 'parses hdop alias for accuracy' do
      expect(result[1][:accuracy]).to eq(12)
    end

    it 'parses precision alias for accuracy' do
      expect(result[2][:accuracy]).to eq(5)
    end

    it 'parses batt alias for battery' do
      expect(result[0][:battery]).to eq(72)
    end

    it 'parses height alias for altitude' do
      expect(result[2][:altitude]).to eq(36.0)
    end
  end
end
