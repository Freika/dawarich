# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/timestamps')

RSpec.describe Timestamps do
  describe '.parse_timestamp' do
    it 'clamps timezone-shifted pre-epoch seconds to the Unix epoch' do
      expect(described_class.parse_timestamp('-3600')).to eq(0)
    end

    it 'clamps pre-epoch dates to the Unix epoch' do
      expect(described_class.parse_timestamp('1969-12-31T23:00:00Z')).to eq(0)
    end
  end
end
