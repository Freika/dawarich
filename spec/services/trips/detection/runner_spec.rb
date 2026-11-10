# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Detection::Runner do
  subject(:run) { described_class.new(user).call }

  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin', 'locale' => 'en' }) }
  let(:place) { create(:place, user:, latitude: 52.52, longitude: 13.405) }

  def point_at(lon, lat, time)
    create(:point, user:, lonlat: "POINT(#{lon} #{lat})", timestamp: time.to_i)
  end

  def at_home(time) = point_at(13.405, 52.52, time)
  def in_lisbon(time) = point_at(-9.1393, 38.7223, time)

  before do
    create(:home, user:, place:)
    at_home(Time.utc(2026, 1, 1, 12)) # the user has been recorded at home
  end

  context 'with a closed stay in Lisbon' do
    before do
      at_home(Time.utc(2026, 10, 10, 6))
      in_lisbon(Time.utc(2026, 10, 10, 14))
      in_lisbon(Time.utc(2026, 10, 14, 9))
      at_home(Time.utc(2026, 10, 14, 18))
    end

    it 'creates the trip for a closed stay in Lisbon' do
      expect { run }.to change(user.trips.origin_detected, :count).by(1)
      expect(described_class.new(user).call).to be_empty # the second run finds it in place
      expect(user.trips.sole).to have_attributes(started_at: Time.utc(2026, 10, 10, 6),
                                                 ended_at: Time.utc(2026, 10, 14, 18))
    end

    it 'removes untouched Detected Trips when the last Home is gone' do
      run
      user.homes.destroy_all
      expect { described_class.new(user).call }.to change(user.trips, :count).by(-1)
    end

    it 'names trips in the language of the user' do
      user.update!(settings: user.settings.merge('locale' => 'de'))
      expect(run.sole.name).to start_with('Reise, ')
    end
  end

  it 'does nothing for a user without a Home' do
    expect(described_class.new(create(:user)).call).to be_empty
  end

  it 'records a skipped long absence and clears it again' do
    in_lisbon(Time.utc(2026, 3, 1, 12))
    in_lisbon(Time.utc(2026, 6, 29, 12))
    at_home(Time.utc(2026, 6, 30, 12))

    expect(run).to be_empty
    expect(user.reload.safe_settings.trip_detection_long_absence?).to be(true)

    user.points.where(timestamp: Time.utc(2026, 2, 1).to_i..Time.utc(2026, 6, 29, 12).to_i).delete_all
    described_class.new(user).call
    expect(user.reload.safe_settings.trip_detection_long_absence?).to be(false)
  end

  it 'keeps the other settings when it writes the long-absence flag' do
    in_lisbon(Time.utc(2026, 3, 1, 12))
    in_lisbon(Time.utc(2026, 6, 29, 12))
    at_home(Time.utc(2026, 6, 30, 12))

    run
    expect(user.reload.settings).to include('timezone' => 'Europe/Berlin', 'locale' => 'en',
                                            'trip_detection_long_absence' => true)
  end
end
