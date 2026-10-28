# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::TimeValue do
  {
    '2024-02-29T10:00:00Z' => Time.utc(2024, 2, 29, 10),
    '2025-06-21 18:42:00 UTC' => Time.utc(2025, 6, 21, 18, 42),
    '2025-06-21T20:42:00+02:00' => Time.utc(2025, 6, 21, 18, 42)
  }.each do |value, expected|
    it "reads #{value}" do
      expect(described_class.parse(value)).to eq(expected)
    end
  end

  ['2025-02-29T10:00:00Z', '2025-06-31', 'Feb 30', '2025-13-01', 'not-a-date', '', nil].each do |value|
    it "rejects #{value.inspect}" do
      expect(described_class.parse(value)).to be_nil
    end
  end
end
