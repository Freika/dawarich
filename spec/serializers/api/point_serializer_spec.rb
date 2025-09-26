# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }
    let(:all_excluded) { Api::PointSerializer::EXCLUDED_ATTRIBUTES }
    let(:expected_json) do
      point.attributes.except(*all_excluded).tap do |attributes|
        # API serializer extracts coordinates from PostGIS geometry
        attributes['latitude'] = point.lat.to_s
        attributes['longitude'] = point.lon.to_s
      end
    end

    it 'returns JSON with correct attributes' do
      expect(serializer.to_json).to eq(expected_json.to_json)
    end

    it 'does not include excluded attributes' do
      expect(serializer).not_to include(*all_excluded)
    end

    it 'extracts coordinates from PostGIS geometry' do
      expect(serializer['latitude']).to eq(point.lat.to_s)
      expect(serializer['longitude']).to eq(point.lon.to_s)
    end
  end
end
