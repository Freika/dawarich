# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculateFlightMonthsJob do
  it 'recalculates only the months that contain flights' do
    flyer = create(:user)
    create(:flight, user: flyer, external_id: 1, flight_date: Date.new(2025, 11, 3))
    create(:flight, user: flyer, external_id: 2, flight_date: Date.new(2026, 3, 31),
                    departure_time: Time.utc(2026, 3, 31, 22), arrival_time: Time.utc(2026, 4, 1, 2))
    create(:user)

    expect { described_class.perform_now }
      .to have_enqueued_job(Stats::CalculatingJob).exactly(3).times
      .and have_enqueued_job(Stats::CalculatingJob).with(flyer.id, 2025, 11)
      .and have_enqueued_job(Stats::CalculatingJob).with(flyer.id, 2026, 3)
      .and have_enqueued_job(Stats::CalculatingJob).with(flyer.id, 2026, 4)
  end
end
