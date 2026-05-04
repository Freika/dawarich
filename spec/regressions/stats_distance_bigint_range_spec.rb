# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stats distance accepts values beyond 4-byte integer range' do
  let(:user) { create(:user) }

  let(:int4_max)        { 2_147_483_647 }
  let(:overflow_meters) { 12_089_677_383 }

  it 'persists a distance just above the int4 maximum' do
    stat = build(:stat, user: user, year: 2026, month: 1, distance: int4_max + 1)

    expect { stat.save! }.not_to raise_error
    expect(stat.reload.distance).to eq(int4_max + 1)
  end

  it 'persists the overflow value reported in the wild without raising' do
    stat = build(:stat, user: user, year: 2026, month: 2, distance: overflow_meters)

    expect { stat.save! }.not_to raise_error
    expect(stat.reload.distance).to eq(overflow_meters)
  end
end
