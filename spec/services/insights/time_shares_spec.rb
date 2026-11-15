# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insights::TimeShares do
  let(:user) { create(:user) }
  let(:home_place) { create(:place, user:) }
  let(:cafe) { create(:place, user:) }
  # A short year keeps the arithmetic readable: 1–10 January 2025.
  let(:today) { Date.new(2025, 1, 10) }

  def at(day, hour) = Time.zone.local(2025, 1, day, hour)

  before do
    create(:home, user:, place: home_place, started_on: Date.new(2024, 1, 1))
    # 2 Jan: a whole day at home, never moving.
    create(:visit, user:, place: home_place, started_at: at(2, 0), ended_at: at(2, 20), duration: 1200)
    # 3 Jan: home in the morning, then out to the café.
    create(:visit, user:, place: home_place, started_at: at(3, 0), ended_at: at(3, 8), duration: 480)
    create(:track, user:, start_at: at(3, 8), end_at: at(3, 9), duration: 3600)
    create(:visit, user:, place: cafe, started_at: at(3, 9), ended_at: at(3, 11), duration: 120)
    # 5–7 Jan: away on a trip.
    create(:trip, user:, started_at: at(5, 10), ended_at: at(7, 18))
    # A declined visit counts for nothing.
    create(:visit, user:, place: cafe, started_at: at(8, 9), ended_at: at(8, 10), duration: 60, status: :declined)
  end

  subject(:shares) { described_class.new(user, 2025, today:).call }

  it 'sorts the days of the year so far into home, out and about, trips and untracked' do
    expect(shares.days).to eq(home: 1, out: 1, trip: 3, untracked: 5)
  end

  it 'splits the hours between home, other places, moving and no data' do
    expect(shares.hours).to eq(home: 28.0, places: 2.0, moving: 1.0, no_data: 209.0)
  end

  it 'has nothing to say about a year that has not started' do
    expect(described_class.new(user, 2026, today:).call).to be_nil
  end
end
