# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::VisitSerializer do
  describe '#call' do
    let(:place) { create(:place) }
    let(:area) { create(:area) }
    let(:visit) { create(:visit, place: place, area: area) }

    subject(:serializer) { described_class.new(visit) }

    it 'serializes a real visit model correctly' do
      result = serializer.call

      expect(result[:id]).to eq(visit.id)
      expect(result[:area_id]).to eq(visit.area_id)
      expect(result[:user_id]).to eq(visit.user_id)
      expect(result[:started_at]).to eq(visit.started_at)
      expect(result[:ended_at]).to eq(visit.ended_at)
      expect(result[:duration]).to eq(visit.duration)
      expect(result[:name]).to eq(visit.name)
      expect(result[:status]).to eq(visit.status)

      expect(result[:place][:id]).to eq(place.id)
      expect(result[:place][:latitude]).to eq(place.lat)
      expect(result[:place][:longitude]).to eq(place.lon)
    end

    context 'confidence fields' do
      it 'exposes confidence and confidence_band when set' do
        visit.update!(confidence: 85)

        result = described_class.new(visit.reload).call

        expect(result[:confidence]).to eq(85)
        expect(result[:confidence_band]).to eq(:high)
      end

      it 'is null-safe when confidence is nil' do
        visit.update!(confidence: nil)

        result = described_class.new(visit.reload).call

        expect(result[:confidence]).to be_nil
        expect(result[:confidence_band]).to be_nil
      end
    end
  end
end
