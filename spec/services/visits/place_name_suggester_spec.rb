# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::PlaceNameSuggester do
  subject(:suggester) { described_class.new(points) }

  describe '#call' do
    context 'when no points have geodata' do
      let(:points) do
        [
          double('Point', geodata: nil),
          double('Point', geodata: {})
        ]
      end

      it 'returns nil' do
        expect(suggester.call).to be_nil
      end
    end

    context 'when points have geodata but no features' do
      let(:points) do
        [
          double('Point', geodata: { 'features' => [] })
        ]
      end

      it 'returns nil' do
        expect(suggester.call).to be_nil
      end
    end

    context 'when features exist but with different types' do
      let(:points) do
        [
          double('Point', geodata: {
                   'features' => [
                     { 'properties' => { 'type' => 'cafe', 'name' => 'Coffee Shop' } },
                     { 'properties' => { 'type' => 'restaurant', 'name' => 'Pizza Place' } }
                   ]
                 })
        ]
      end

      it 'returns the name of the most common type' do
        # Since both types appear once, it will pick the first one alphabetically in practice
        expect(suggester.call).to eq('Coffee Shop')
      end
    end

    context 'when features have a common type but different names' do
      let(:points) do
        [
          double('Point', geodata: {
                   'features' => [
                     { 'properties' => { 'type' => 'park', 'name' => 'Central Park' } }
                   ]
                 }),
          double('Point', geodata: {
                   'features' => [
                     { 'properties' => { 'type' => 'park', 'name' => 'City Park' } }
                   ]
                 }),
          double('Point', geodata: {
                   'features' => [
                     { 'properties' => { 'type' => 'park', 'name' => 'Central Park' } }
                   ]
                 })
        ]
      end

      it 'returns the most common name' do
        expect(suggester.call).to eq('Central Park')
      end
    end

    context 'when a complete place can be built' do
      let(:points) do
        [
          double('Point', geodata: {
                   'features' => [
                     {
                       'properties' => {
                         'type' => 'cafe',
                         'name' => 'Starbucks',
                         'street' => '123 Main St',
                         'city' => 'San Francisco',
                         'state' => 'CA'
                       }
                     }
                   ]
                 })
        ]
      end

      it 'returns a descriptive name with all components' do
        expect(suggester.call).to eq('Starbucks, 123 Main St, San Francisco, CA')
      end
    end

    context 'when only partial place details are available' do
      let(:points) do
        [
          double('Point', geodata: {
                   'features' => [
                     {
                       'properties' => {
                         'type' => 'cafe',
                         'name' => 'Starbucks',
                         'city' => 'San Francisco'
                         # No street or state
                       }
                     }
                   ]
                 })
        ]
      end

      it 'returns a name with available components' do
        expect(suggester.call).to eq('Starbucks, San Francisco')
      end
    end

    context 'when points have geodata with non-array features' do
      let(:points) do
        [
          double('Point', geodata: { 'features' => 'not an array' })
        ]
      end

      it 'returns nil' do
        expect(suggester.call).to be_nil
      end
    end

    context 'when most common name is blank' do
      let(:points) do
        [
          double('Point', geodata: {
                   'features' => [
                     { 'properties' => { 'type' => 'road', 'name' => '' } }
                   ]
                 })
        ]
      end

      it 'returns nil' do
        expect(suggester.call).to be_nil
      end
    end
  end
end
