# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VectorTileTimeout do
  describe '.query_timeout_ms' do
    around do |example|
      original = ENV.fetch('VECTOR_TILES_QUERY_TIMEOUT_MS', nil)
      example.run
    ensure
      if original.nil?
        ENV.delete('VECTOR_TILES_QUERY_TIMEOUT_MS')
      else
        ENV['VECTOR_TILES_QUERY_TIMEOUT_MS'] = original
      end
    end

    it 'defaults to 5000 when the variable is unset' do
      ENV.delete('VECTOR_TILES_QUERY_TIMEOUT_MS')

      expect(described_class.query_timeout_ms).to eq(5_000)
    end

    it 'returns the configured integer value' do
      ENV['VECTOR_TILES_QUERY_TIMEOUT_MS'] = '30000'

      expect(described_class.query_timeout_ms).to eq(30_000)
    end

    it 'falls back to the default on a non-numeric value' do
      ENV['VECTOR_TILES_QUERY_TIMEOUT_MS'] = 'unlimited'

      expect(described_class.query_timeout_ms).to eq(5_000)
    end

    it 'falls back to the default on a non-positive value' do
      ENV['VECTOR_TILES_QUERY_TIMEOUT_MS'] = '0'

      expect(described_class.query_timeout_ms).to eq(5_000)
    end
  end
end
