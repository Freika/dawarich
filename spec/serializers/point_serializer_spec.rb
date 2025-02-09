# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }
    let(:expected_json) do
      point.attributes.except(*PointSerializer::EXCLUDED_ATTRIBUTES).merge(
        city: point.city_name,
        country: point.country_name
      )
    end

    it 'returns JSON' do
      expect(serializer.to_json).to eq(expected_json.to_json)
    end

    it 'does not include excluded attributes' do
      expect(serializer).not_to include(*PointSerializer::EXCLUDED_ATTRIBUTES)
    end
  end
end
