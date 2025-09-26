# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonCenterManager do
  describe '.call' do
    subject(:manage_centers) { described_class.new(stat:, user:).call }

    let(:user) { create(:user) }
    let(:target_user) { user }

    context 'with pre-calculated hexagon centers' do
      let(:pre_calculated_centers) do
        [
          ['8a1fb46622dffff', 5, 1_717_200_000, 1_717_203_600], # h3_index, count, earliest, latest timestamps
          ['8a1fb46622e7fff', 3, 1_717_210_000, 1_717_213_600],
          ['8a1fb46632dffff', 8, 1_717_220_000, 1_717_223_600]
        ]
      end
      let(:stat) { create(:stat, user:, year: 2024, month: 6, h3_hex_ids: pre_calculated_centers) }

      it 'returns success with pre-calculated data' do
        result = manage_centers

        expect(result[:success]).to be true
        expect(result[:pre_calculated]).to be true
        expect(result[:data]['type']).to eq('FeatureCollection')
        expect(result[:data]['features'].length).to eq(3)
        expect(result[:data]['metadata']['pre_calculated']).to be true
        expect(result[:data]['metadata']['count']).to eq(3)
        expect(result[:data]['metadata']['user_id']).to eq(target_user.id)
      end

      it 'generates proper hexagon features from centers' do
        result = manage_centers
        features = result[:data]['features']

        features.each_with_index do |feature, index|
          expect(feature['type']).to eq('Feature')
          expect(feature['id']).to eq(index + 1)
          expect(feature['geometry']['type']).to eq('Polygon')
          expect(feature['geometry']['coordinates'].first.length).to eq(7) # 6 vertices + closing

          properties = feature['properties']
          expect(properties['hex_id']).to eq(index + 1)
          expect(properties['earliest_point']).to be_present
          expect(properties['latest_point']).to be_present
        end
      end
    end


    context 'with no stat' do
      let(:stat) { nil }

      it 'returns nil' do
        expect(manage_centers).to be_nil
      end
    end

    context 'with stat but no hexagon_centers' do
      let(:stat) { create(:stat, user:, year: 2024, month: 6, h3_hex_ids: nil) }

      it 'returns nil' do
        expect(manage_centers).to be_nil
      end
    end

    context 'with empty hexagon_centers' do
      let(:stat) { create(:stat, user:, year: 2024, month: 6, h3_hex_ids: []) }

      it 'returns nil' do
        expect(manage_centers).to be_nil
      end
    end
  end
end
