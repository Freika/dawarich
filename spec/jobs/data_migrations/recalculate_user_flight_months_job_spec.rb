# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculateUserFlightMonthsJob do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }

  before do
    create(:flight, user:)
    create(:point, user:, timestamp: Time.utc(2026, 4, 20, 8).to_i, lonlat: 'POINT(13.4 52.5)')
    create(:point, user:, timestamp: Time.utc(2026, 4, 20, 9).to_i, lonlat: 'POINT(13.41 52.51)')
  end

  it 'counts the flights in the monthly and yearly digests the user already has' do
    monthly = create(:users_digest, user:, year: 2026, month: 4, period_type: :monthly, distance: 0, flight_distance: 0)
    yearly = create(:users_digest, user:, year: 2026, period_type: :yearly, distance: 0)

    described_class.perform_now(user.id)

    expect(user.stats.find_by(year: 2026, month: 4).flight_distance).to be_positive
    expect(monthly.reload).to have_attributes(flight_distance: be_positive, distance: be_positive)
    expect(yearly.reload.distance).to be_positive
  end

  it 'creates no digest the user did not have' do
    expect { described_class.perform_now(user.id) }.not_to change(Users::Digest, :count)
  end
end
