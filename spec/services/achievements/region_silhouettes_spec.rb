# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::RegionSilhouettes do
  let(:bavaria) { 'MULTIPOLYGON (((11.0 48.0, 11.0 49.0, 12.0 49.0, 12.0 48.0, 11.0 48.0)))' }

  def multipolygon(*boxes)
    rings = boxes.map do |xmin, ymin, xmax, ymax|
      "((#{xmin} #{ymin}, #{xmin} #{ymax}, #{xmax} #{ymax}, #{xmax} #{ymin}, #{xmin} #{ymin}))"
    end
    "MULTIPOLYGON (#{rings.join(', ')})"
  end

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

  describe 'card framing' do
    {
      'FR' => [[-5, 43, 8, 51], [-54, 2, -51, 6]],
      'PT' => [[-9, 37, -6.5, 42], [-31, 37, -25, 40]],
      'NO' => [[5, 58, 31, 71], [3, -55, 4, -54], [15, 76, 25, 80]],
      'NL' => [[3.5, 51, 7, 53.5], [-69, 12, -68, 13]],
      'ES' => [[-9, 36, 3, 44], [-18, 27, -13, 29]]
    }.each do |code, boxes|
      it "frames #{code}'s mainland without changing its stored overseas boundaries" do
        country = create(:country, iso_a2: code, geom: multipolygon(*boxes))
        original = country.geom.as_text

        shape = described_class.new(level: :country, codes: [code]).call.fetch(code)

        xmin, ymin, xmax, ymax = boxes.first
        expect(shape[:viewbox].split.map(&:to_f)).to eq([xmin, -ymax, xmax - xmin, ymax - ymin])
        expect(country.reload.geom.as_text).to eq(original)
      end
    end

    it 'keeps both sides of an antimeridian country together without a world-wide bounding box' do
      create(:country, iso_a2: 'RU', geom: multipolygon([30, 50, 179, 70], [-180, 60, -170, 70]))

      shape = described_class.new(level: :country, codes: ['RU']).call.fetch('RU')

      expect(shape[:viewbox].split.map(&:to_f)[2]).to be < 200
      expect(shape[:path].scan(/M/).size).to eq(2)
    end

    it 'retains Corsica and the Balearics beside their mainland polygons' do
      create(:country, iso_a2: 'FR', geom: multipolygon([-5, 43, 8, 51], [8.5, 41.5, 9.5, 43]))
      create(:country, iso_a2: 'ES', geom: multipolygon([-9, 36, 3, 44], [3.5, 39, 4, 40]))

      shapes = described_class.new(level: :country, codes: %w[FR ES]).call

      expect(shapes.values.map { |shape| shape[:path].scan(/M/).size }).to eq([2, 2])
    end

    it 'does not discard islands or separate land masses of other countries' do
      create(:country, iso_a2: 'ID', geom: multipolygon([95, -5, 105, 5], [130, -8, 141, -3]))

      shape = described_class.new(level: :country, codes: ['ID']).call.fetch('ID')

      expect(shape[:viewbox].split.map(&:to_f)).to eq([95, -5, 46, 13])
      expect(shape[:path].scan(/M/).size).to eq(2)
    end
  end

  describe '.collection' do
    it 'frames Europe without Russian Pacific territory or overseas possessions' do
      create(:country, iso_a2: 'FR', geom: multipolygon([-5, 43, 8, 51], [-54, 2, -51, 6]))
      create(:country, iso_a2: 'RU', geom: multipolygon([30, 50, 179, 70], [-180, 60, -170, 70]))
      create(:country, iso_a2: 'NO', geom: multipolygon([5, 58, 31, 71], [3, -55, 4, -54]))

      shape = described_class.collection(codes: %w[FR RU NO], key: 'continent_europe')

      expect(shape[:viewbox].split.map(&:to_f)).to eq([-5, -71, 65, 28])
      expect(shape[:path].scan(/M/).size).to eq(3)
      expect(shape[:path]).not_to include(';')
    end

    it 'uses original boundaries for world collections, not the individual mainland crops' do
      create(:country, iso_a2: 'FR', geom: multipolygon([-5, 43, 8, 51], [-54, 2, -51, 6]))
      described_class.new(level: :country, codes: ['FR']).call
      described_class.collection(codes: ['FR'], key: 'continent_europe')

      shape = described_class.collection(codes: ['FR'], key: 'world_wanderer')

      expect(shape[:viewbox].split.map(&:to_f)).to eq([-54, -51, 62, 49])
      expect(shape[:path].scan(/M/).size).to eq(2)
    end

    it 'unwraps Pacific countries in the same longitude domain' do
      create(:country, iso_a2: 'NZ', geom: multipolygon([166, -46, 178, -35]))
      create(:country, iso_a2: 'FJ', geom: multipolygon([177, -19, 180, -16], [-180, -19, -178, -16]))

      shape = described_class.collection(codes: %w[NZ FJ], key: 'continent_oceania')

      expect(shape[:viewbox].split.map(&:to_f)).to eq([166, 16, 16, 30])
      expect(shape[:path].scan(/M/).size).to eq(3)
    end

    it 'does not shift a world map across Greenwich just to save a few degrees' do
      create(:country, iso_a2: 'US', geom: multipolygon([-180, -50, -30, 50]))
      create(:country, iso_a2: 'GB', geom: multipolygon([-5, -2, 5, 2]))
      create(:country, iso_a2: 'RU', geom: multipolygon([30, -50, 180, 50]))

      shape = described_class.collection(codes: %w[US GB RU], key: 'world_wanderer')

      expect(shape[:viewbox].split.map(&:to_f)).to eq([-180, -50, 360, 100])
    end

    it 'caches collections separately by member codes and framing key' do
      create(:country, iso_a2: 'DE', geom: bavaria)
      shape = described_class.collection(codes: ['DE'], key: 'continent_europe')
      Country.delete_all

      expect(described_class.collection(codes: ['DE'], key: 'continent_europe')).to eq(shape)
      expect(described_class.collection(codes: ['FR'], key: 'continent_europe')).to be_nil
      expect(described_class.collection(codes: ['DE'])).to be_nil
    end

    it 'combines country paths in one geographic frame without raster maps' do
      create(:country, iso_a2: 'DE', geom: bavaria)
      create(:country, iso_a2: 'FR', geom: 'MULTIPOLYGON (((2 45, 2 47, 4 47, 4 45, 2 45)))')

      shape = described_class.collection(codes: %w[DE FR])

      expect(shape[:viewbox].split.map(&:to_f)).to eq([2.0, -49.0, 10.0, 4.0])
      expect(shape[:path].scan(/M/).size).to eq(2)
      expect(shape[:path]).not_to include(';')
    end

    it 'returns no fabricated shape when boundaries are unavailable' do
      expect(described_class.collection(codes: ['XX'])).to be_nil
    end
  end
end
