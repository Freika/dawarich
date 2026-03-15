# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::DigestListSerializer do
  let(:user) { create(:user) }
  let(:digest) { create(:users_digest, user: user, distance: 500_000) }

  describe '#call' do
    subject(:result) do
      described_class.new(digests: [digest], available_years: [2023]).call
    end

    it 'returns raw distance value' do
      expect(result[:digests].first[:distance]).to eq(500_000)
    end

    it 'includes available years' do
      expect(result[:availableYears]).to eq([2023])
    end

    it 'serializes all digest fields' do
      serialized = result[:digests].first

      expect(serialized).to include(
        year: digest.year,
        distance: digest.distance,
        countriesCount: digest.countries_count,
        citiesCount: digest.cities_count
      )
      expect(serialized[:createdAt]).to eq(digest.created_at.iso8601)
    end
  end
end
