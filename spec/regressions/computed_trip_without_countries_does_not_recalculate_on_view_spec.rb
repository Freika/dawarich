# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Viewing a computed trip without country data', type: :request do
  it 'does not enqueue a full recalculation on repeated views after calculation completes' do
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)

    user = create(:user)
    started_at = Time.utc(2024, 5, 1, 12)
    trip = create(:trip, user:, name: 'Synthetic ocean trip', started_at:,
                         ended_at: started_at + 1.hour, path: nil, distance: nil,
                         skip_calculation_enqueue: true)

    3.times do |index|
      create(:point, user:, timestamp: started_at.to_i + index * 60,
                     lonlat: "POINT(#{-140.0 + index * 0.001} -40.0)", country_name: nil)
    end

    expect(trip.points.count).to eq(3)
    expect(trip.points.pluck(:country_name)).to eq([nil, nil, nil])

    perform_enqueued_jobs(only: [Trips::CalculateAllJob, Trips::CalculatePathJob,
                                 Trips::CalculateDistanceJob, Trips::CalculateCountriesJob]) do
      Trips::CalculateAllJob.perform_later(trip.id, 'km')
    end

    trip.reload
    expect(trip.path).to be_present
    expect(trip.distance).to be_positive
    expect(trip.visited_countries).to eq([])

    sign_in user

    expect do
      2.times do
        get trip_path(trip)
        expect(response).to have_http_status(:ok)
      end
    end.not_to have_enqueued_job(Trips::CalculateAllJob)
  end

  it 'still enqueues a recalculation when the trip has no path yet' do
    user = create(:user)
    started_at = Time.utc(2024, 5, 1, 12)
    trip = create(:trip, user:, name: 'Uncalculated trip', started_at:, ended_at: started_at + 1.hour,
                         path: nil, distance: nil, visited_countries: ['Ocean'], skip_calculation_enqueue: true)

    sign_in user

    expect { get trip_path(trip) }.to have_enqueued_job(Trips::CalculateAllJob).with(trip.id, 'km')
  end
end
