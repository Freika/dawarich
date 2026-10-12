# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::StreamHandler do
  def parse(payload, &block)
    handler = described_class.new(&block)
    parser = Oj::Parser.new(:saj, handler:)
    parser.load(StringIO.new(Oj.dump(payload, mode: :compat)))
  end

  it 'yields each feature in a FeatureCollection independently' do
    features = [
      {
        'type' => 'Feature',
        'geometry' => { 'type' => 'Point', 'coordinates' => [13.4, 52.5] },
        'properties' => { 'timestamp' => 1_609_459_201 }
      },
      {
        'type' => 'Feature',
        'geometry' => { 'type' => 'LineString', 'coordinates' => [[13.5, 52.6, 0, 1_609_459_262]] },
        'properties' => {}
      }
    ]
    yielded = []

    parse({ 'type' => 'FeatureCollection', 'name' => 'Synthetic', 'features' => features }) do |feature|
      yielded << feature
    end

    expect(yielded).to eq(features)
  end

  it 'preserves support for a single top-level Feature' do
    feature = {
      'type' => 'Feature',
      'geometry' => { 'type' => 'Point', 'coordinates' => [13.4, 52.5] },
      'properties' => { 'timestamp' => 1_609_459_201 }
    }
    yielded = []

    parse(feature) { |value| yielded << value }

    expect(yielded).to eq([feature])
  end

  it 'does not yield objects from unrelated top-level arrays' do
    yielded = []

    parse({ 'type' => 'FeatureCollection', 'metadata' => [{ 'source' => 'Synthetic' }], 'features' => [] }) do |feature|
      yielded << feature
    end

    expect(yielded).to be_empty
  end

  it 'does not stream a features array when the root type is not FeatureCollection' do
    feature = {
      'type' => 'Feature',
      'geometry' => { 'type' => 'Point', 'coordinates' => [13.4, 52.5] },
      'properties' => {}
    }
    yielded = []

    parse({ 'type' => 'Topology', 'features' => [feature] }) { |value| yielded << value }

    expect(yielded).to be_empty
  end
end
