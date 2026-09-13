# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip distance accepts values beyond the 4-byte integer range' do
  let(:trip) { create(:trip) }
  let(:int4_max) { 2_147_483_647 }

  it 'persists a recalculated trip distance above the int4 maximum' do
    allow(Point).to receive(:total_distance).and_return(int4_max + 1)

    expect { trip.recalculate_distance! }.not_to raise_error
    expect(trip.reload.distance).to eq(int4_max + 1)
  end
end
