# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::FieldAliases do
  let(:test_class) { Class.new { include Imports::FieldAliases } }
  let(:instance) { test_class.new }

  describe '#find_field' do
    let(:properties) do
      { 'lat' => 51.5, 'lon' => -0.12, 'datetime' => '2024-01-15T10:00:00Z',
        'ele' => 120.5, 'vel' => 3.5, 'acc' => 10, 'batt' => 85,
        'bearing' => 180, 'tid' => 'AB' }
    end

    it 'finds latitude by alias' do
      expect(instance.find_field(properties, :latitude)).to eq(51.5)
    end

    it 'finds longitude by alias' do
      expect(instance.find_field(properties, :longitude)).to eq(-0.12)
    end

    it 'finds timestamp by alias datetime' do
      expect(instance.find_field(properties, :timestamp)).to eq('2024-01-15T10:00:00Z')
    end

    it 'finds altitude by alias ele' do
      expect(instance.find_field(properties, :altitude)).to eq(120.5)
    end

    it 'finds speed by alias vel' do
      expect(instance.find_field(properties, :speed)).to eq(3.5)
    end

    it 'finds accuracy by alias acc' do
      expect(instance.find_field(properties, :accuracy)).to eq(10)
    end

    it 'finds battery by alias batt' do
      expect(instance.find_field(properties, :battery)).to eq(85)
    end

    it 'finds heading by alias bearing' do
      expect(instance.find_field(properties, :heading)).to eq(180)
    end

    it 'finds tracker_id by alias tid' do
      expect(instance.find_field(properties, :tracker_id)).to eq('AB')
    end

    it 'returns nil for missing field' do
      expect(instance.find_field({}, :latitude)).to be_nil
    end

    it 'is case-insensitive' do
      props = { 'Latitude' => 51.5, 'LONGITUDE' => -0.12 }
      expect(instance.find_field(props, :latitude)).to eq(51.5)
      expect(instance.find_field(props, :longitude)).to eq(-0.12)
    end
  end

  describe '#find_header' do
    it 'finds latitude column index' do
      headers = %w[time lat lon ele]
      expect(instance.find_header(headers, :latitude)).to eq(1)
    end

    it 'finds longitude by lng alias' do
      headers = %w[timestamp lng latitude altitude]
      expect(instance.find_header(headers, :longitude)).to eq(1)
    end

    it 'is case-insensitive' do
      headers = %w[Time LATITUDE Longitude]
      expect(instance.find_header(headers, :latitude)).to eq(1)
      expect(instance.find_header(headers, :longitude)).to eq(2)
    end

    it 'returns nil for missing header' do
      headers = %w[foo bar baz]
      expect(instance.find_header(headers, :latitude)).to be_nil
    end
  end

  describe '#speed_kmh_alias?' do
    it 'returns true for speed_kmh' do
      expect(instance.speed_kmh_alias?('speed_kmh')).to be true
    end

    it 'returns false for speed' do
      expect(instance.speed_kmh_alias?('speed')).to be false
    end
  end
end
