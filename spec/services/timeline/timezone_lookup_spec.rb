# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::TimezoneLookup do
  describe '.call' do
    it 'returns the IANA timezone for coordinates' do
      expect(described_class.call(39.0997, -94.5786)).to eq('America/Chicago')
    end

    it 'returns nil when coordinates are unavailable' do
      expect(described_class.call(nil, nil)).to be_nil
    end
  end
end
