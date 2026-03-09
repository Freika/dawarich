# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::DigestListSerializer do
  let(:user) { create(:user) }
  let(:digest) { create(:users_digest, user: user, distance: 500_000) }

  describe '#call' do
    context 'with km unit' do
      subject(:result) do
        described_class.new(digests: [digest], available_years: [2023], distance_unit: 'km').call
      end

      it 'returns converted distance in km' do
        distance = result[:digests].first[:distance]
        expect(distance[:converted]).to eq(500)
        expect(distance[:unit]).to eq('km')
        expect(distance[:meters]).to eq(500_000)
      end

      it 'includes available years' do
        expect(result[:availableYears]).to eq([2023])
      end
    end

    context 'with mi unit' do
      subject(:result) do
        described_class.new(digests: [digest], available_years: [], distance_unit: 'mi').call
      end

      it 'returns converted distance in miles' do
        distance = result[:digests].first[:distance]
        expect(distance[:converted]).to eq(311)
        expect(distance[:unit]).to eq('mi')
        expect(distance[:meters]).to eq(500_000)
      end
    end

    context 'with default unit' do
      subject(:result) do
        described_class.new(digests: [digest], available_years: []).call
      end

      it 'defaults to km' do
        distance = result[:digests].first[:distance]
        expect(distance[:unit]).to eq('km')
        expect(distance[:converted]).to eq(500)
      end
    end
  end
end
