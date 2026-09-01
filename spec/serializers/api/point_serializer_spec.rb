# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }
    let(:all_excluded) { Api::PointSerializer::EXCLUDED_ATTRIBUTES }
    let(:expected_json) do
      point.attributes.except(*all_excluded).tap do |attributes|
        attributes['latitude'] = point.lat.to_s
        attributes['longitude'] = point.lon.to_s
        attributes['country_name'] = point.country_name
        attributes['velocity'] = point.velocity&.to_s
        PointDimensionReads::DIMENSION_ATTRIBUTES.each do |attribute|
          attributes[attribute] = point.public_send(attribute)
        end
      end
    end

    context 'when the point is stamped with a dimension row' do
      before do
        source = PointSource.create!(digest: 'a' * 32, tracker_id: 'dimension-device',
                                     connection: 'wifi')
        point.update_columns(source_id: source.id)
        point.reload
      end

      it 'emits the device combo from the dimension, under the same keys' do
        expect(serializer['tracker_id']).to eq('dimension-device')
        expect(serializer['connection']).to eq('wifi')
        expect(serializer.keys).to eq(expected_json.keys)
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
