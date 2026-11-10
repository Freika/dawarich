# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Home, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:place) { create(:place, user:) }

  it 'is valid with both dates open' do
    expect(build(:home, user:, place:, started_on: nil, ended_on: nil)).to be_valid
  end

  it 'rejects an end before the start' do
    home = build(:home, user:, place:, started_on: Date.new(2022, 3, 1), ended_on: Date.new(2022, 2, 1))
    expect(home).not_to be_valid
  end

  it "rejects another user's place" do
    expect(build(:home, user:, place: create(:place))).not_to be_valid
  end

  it 'allows two periods at one place' do
    create(:home, user:, place:, ended_on: Date.new(2015, 1, 1))
    expect(build(:home, user:, place:, started_on: Date.new(2020, 1, 1))).to be_valid
  end

  it 'builds a place of its own user by default' do
    home = build(:home)
    expect(home.place.user).to eq(home.user)
  end

  describe '.in_effect_on' do
    it 'treats open ends as unbounded and both dates as inclusive' do
      past = create(:home, user:, place:, ended_on: Date.new(2022, 3, 1))
      current = create(:home, user:, place:, started_on: Date.new(2022, 3, 15))
      expect(Home.in_effect_on(Date.new(2022, 3, 1))).to contain_exactly(past)
      expect(Home.in_effect_on(Date.new(2022, 3, 10))).to be_empty
      expect(Home.in_effect_on(Date.new(2022, 3, 15))).to contain_exactly(current)
    end
  end

  it 'is removed with its place' do
    create(:home, user:, place:)
    expect { Places::Destroy.new(user:, place:).call }.to change(Home, :count).by(-1)
  end

  it 'does not block the hard deletion of its user' do
    create(:home, user:, place:)
    expect { Users::Destroy.new(user).call }.to change(Home, :count).by(-1)
  end

  it 'is listed on its user and place' do
    home = create(:home, user:, place:)
    expect(user.homes).to contain_exactly(home)
    expect(place.homes).to contain_exactly(home)
  end

  def schedules_detection
    have_enqueued_job(Trips::DetectJob).with(user.id).at(Trips::DetectJob::DEBOUNCE_DELAY.from_now)
  end

  it 'schedules detection when created, changed or removed' do
    freeze_time do
      home = nil
      clear_trip_detection_schedule(user.id)
      expect { home = create(:home, user:, place:) }.to schedules_detection
      clear_trip_detection_schedule(user.id)
      expect { home.update!(ended_on: Date.new(2026, 1, 1)) }.to schedules_detection
      clear_trip_detection_schedule(user.id)
      expect { home.destroy! }.to schedules_detection
    end
  end

  it 'schedules detection when its place moves, and not for a place without a Home' do
    create(:home, user:, place:)
    other = create(:place, user:)
    freeze_time do
      clear_trip_detection_schedule(user.id)
      expect { place.update!(latitude: 48.85, longitude: 2.35) }.to schedules_detection
      expect(place.reload.lonlat.y).to eq(48.85)
      clear_trip_detection_schedule(user.id)
      expect { other.update!(latitude: 48.85, longitude: 2.35) }.not_to have_enqueued_job(Trips::DetectJob)
    end
  end

  it 'does not schedule detection when its place changes without moving' do
    create(:home, user:, place:)
    clear_trip_detection_schedule(user.id)
    expect { place.update!(name: 'Elsewhere') }.not_to have_enqueued_job(Trips::DetectJob)
  end
end
