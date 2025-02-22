# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::CreatePathJob, type: :job do
  let!(:trip) { create(:trip, :with_points) }
  let(:points) { trip.points }
  let(:trip_path) do
    "LINESTRING (#{points.map do |point|
      "#{point.lon.to_f.round(5)} #{point.lat.to_f.round(5)}"
    end.join(', ')})"
  end

  before do
    trip.update(path: nil, distance: nil)
  end

  it 'creates a path for a trip' do
    described_class.perform_now(trip.id)

    expect(trip.reload.path.to_s).to eq(trip_path)
  end
end
