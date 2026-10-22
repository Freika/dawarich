# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map bounds for a dense part of a long history' do
  it 'keeps both ends of the occupied period when the full aggregation times out' do
    user = create(:user)
    create(:point, user:, latitude: 52.5, longitude: 13.4, timestamp: Time.utc(2024, 6, 15, 10).to_i)
    create(:point, user:, latitude: 40.7, longitude: -74.0, timestamp: Time.utc(2024, 6, 15, 15).to_i)
    calculator = Maps::BoundsCalculator.new(
      user:, start_date: Time.utc(2020, 1, 1).to_i, end_date: Time.utc(2026, 1, 1).to_i, robust: true
    )
    allow(calculator).to receive(:execute_cell_bounds_query).and_raise(ActiveRecord::QueryCanceled)

    result = calculator.call

    expect(result).to include(success: true)
    expect(result[:data]).to include(min_lng: -74.0, max_lng: 13.4, approximate: true, point_count: nil)
  end
end
