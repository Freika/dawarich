# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilter, 'signed point epochs' do
  let(:user) { create(:user) }

  it 'does not run the speed subtraction for fewer than three context points' do
    create(:point, user:, timestamp: -1_000_000_000, lonlat: 'POINT(13.405 52.52)', accuracy: 10)
    create(:point, user:, timestamp: 1_700_000_000, lonlat: 'POINT(13.405 52.52)', accuracy: 10)
    expect(described_class.new(user.id, 1_700_000_000, 1_700_000_000).call).to eq(0)
  end

  it 'retains the raw widened-context bound failure outside the stored int32 epoch range' do
    expect { described_class.new(user.id, -2_147_483_648, -2_147_483_648).call }
      .to raise_error(ActiveRecord::RangeError, /out of range/)
  end
end
