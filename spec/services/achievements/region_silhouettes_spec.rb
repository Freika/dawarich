# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::RegionSilhouettes do
  let(:bavaria) { 'MULTIPOLYGON (((11.0 48.0, 11.0 49.0, 12.0 49.0, 12.0 48.0, 11.0 48.0)))' }

  describe 'building outlines' do
    before { create(:region, code: 'DE-BY', geom: bavaria) }

    it 'returns a path and a viewbox for a known code' do
      shapes = described_class.new(level: :subdivision, codes: %w[DE-BY]).call

      expect(shapes['DE-BY'][:path]).to be_present
      expect(shapes['DE-BY'][:viewbox].split.size).to eq(4)
    end

    it 'negates the y axis so the viewbox matches SVG orientation' do
      shapes = described_class.new(level: :subdivision, codes: %w[DE-BY]).call

      expect(shapes['DE-BY'][:viewbox].split.map(&:to_f)).to eq([11.0, -49.0, 1.0, 1.0])
    end

    it 'omits a code with no stored geometry' do
      expect(described_class.new(level: :subdivision, codes: %w[DE-XX]).call).to eq({})
    end

    it 'returns nothing for an unknown level' do
      expect(described_class.new(level: :planet, codes: %w[DE-BY]).call).to eq({})
    end
  end

  describe 'caching' do
    before { create(:region, code: 'DE-BY', geom: bavaria) }

    it 'serves a repeat lookup without touching the geometry row' do
      described_class.new(level: :subdivision, codes: %w[DE-BY]).call
      Region.delete_all

      shapes = described_class.new(level: :subdivision, codes: %w[DE-BY]).call

      expect(shapes['DE-BY'][:path]).to be_present
    end

    it 'does not re-query a code already known to have no geometry' do
      described_class.new(level: :subdivision, codes: %w[DE-XX]).call
      create(:region, code: 'DE-XX', geom: bavaria)

      expect(described_class.new(level: :subdivision, codes: %w[DE-XX]).call).to eq({})
    end
  end
end
