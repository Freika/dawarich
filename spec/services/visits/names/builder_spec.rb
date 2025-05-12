# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Names::Builder do
  describe '.build_from_properties' do
    it 'builds a name from all available properties' do
      properties = {
        'name' => 'Coffee Shop',
        'street' => 'Main St',
        'housenumber' => '123',
        'city' => 'New York',
        'state' => 'NY'
      }

      result = described_class.build_from_properties(properties)
      expect(result).to eq('Coffee Shop, Main St, 123, New York, NY')
    end

    it 'handles missing properties' do
      properties = {
        'name' => 'Coffee Shop',
        'city' => 'New York',
        'state' => 'NY'
      }

      result = described_class.build_from_properties(properties)
      expect(result).to eq('Coffee Shop, New York, NY')
    end

    it 'deduplicates components' do
      properties = {
        'name' => 'New York Cafe',
        'city' => 'New York',
        'state' => 'NY'
      }

      result = described_class.build_from_properties(properties)
      expect(result).to eq('New York Cafe, New York, NY')
    end

    it 'returns nil for empty properties' do
      result = described_class.build_from_properties({})
      expect(result).to be_nil
    end

    it 'returns nil for nil properties' do
      result = described_class.build_from_properties(nil)
      expect(result).to be_nil
    end
  end

  describe '#call' do
    subject { described_class.new(features, feature_type, name).call }

    let(:feature_type) { 'amenity' }
    let(:name) { 'Coffee Shop' }
    let(:features) do
      [
        {
          'properties' => {
            'type' => 'amenity',
            'name' => 'Coffee Shop',
            'street' => '123 Main St',
            'city' => 'San Francisco',
            'state' => 'CA'
          }
        },
        {
          'properties' => {
            'type' => 'park',
            'name' => 'Central Park',
            'city' => 'New York',
            'state' => 'NY'
          }
        }
      ]
    end

    it 'returns a descriptive name with all available components' do
      expect(subject).to eq('Coffee Shop, 123 Main St, San Francisco, CA')
    end

    context 'when feature uses osm_value instead of type' do
      let(:features) do
        [
          {
            'properties' => {
              'osm_value' => 'amenity',
              'name' => 'Coffee Shop',
              'street' => '123 Main St',
              'city' => 'San Francisco',
              'state' => 'CA'
            }
          }
        ]
      end

      it 'finds the feature using osm_value' do
        expect(subject).to eq('Coffee Shop, 123 Main St, San Francisco, CA')
      end
    end

    context 'when no matching feature is found' do
      let(:name) { 'Non-existent Shop' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'with empty inputs' do
      it 'returns nil for empty features' do
        expect(described_class.new([], feature_type, name).call).to be_nil
      end

      it 'returns nil for blank feature_type' do
        expect(described_class.new(features, '', name).call).to be_nil
      end

      it 'returns nil for blank name' do
        expect(described_class.new(features, feature_type, '').call).to be_nil
      end
    end
  end
end
