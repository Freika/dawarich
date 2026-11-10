# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Detection::Reconciler do
  subject(:created) { described_class.new(user, [candidate]).call }

  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
  let(:candidate) { Trips::Detection::Candidates::Candidate.new(Time.utc(2026, 10, 10, 8), Time.utc(2026, 10, 14, 20)) }

  around { |example| I18n.with_locale(:en) { example.run } }

  def point_at(time, city: nil, country: nil)
    create(:point, user:, timestamp: time.to_i, city:, country:)
  end

  # Runs the block once, right after the reconciler has read the trips it may
  # replace: a user's edit that lands in the middle of a run.
  def during_the_run(edit, &run)
    fired = false
    on_sql = lambda do |*, payload|
      sql = payload[:sql]
      next if fired || !sql.start_with?('SELECT "trips".*') || !sql.include?('"user_edited_at" IS NULL')

      fired = true
      edit.call
    end
    ActiveSupport::Notifications.subscribed(on_sql, 'sql.active_record', &run)
    expect(fired).to be(true)
  end

  it 'creates a Detected Trip for a free period' do
    expect(created.size).to eq(1)
    expect(created.first).to have_attributes(origin: 'detected', started_at: candidate.started_at,
                                             ended_at: candidate.ended_at, name: be_present)
    expect(created.first).to be_persisted
  end

  it 'enqueues the route calculation for the new trip' do
    expect { created }.to have_enqueued_job(Trips::CalculateAllJob)
  end

  # Review Focus 5
  it 'creates nothing on a second run and keeps the id' do
    first = created.first
    expect(described_class.new(user, [candidate]).call).to be_empty
    expect(user.trips.pluck(:id)).to eq([first.id])
  end

  it 'yields to a manual trip that overlaps' do
    create(:trip, user:, started_at: Time.utc(2026, 10, 14, 0), ended_at: Time.utc(2026, 10, 20, 0))
    expect(created).to be_empty
  end

  it 'yields to a trip that only touches the period at its last instant' do
    create(:trip, user:, started_at: candidate.ended_at, ended_at: Time.utc(2026, 10, 20, 0))
    expect(created).to be_empty
  end

  it 'creates the trip next to a manual trip that ends before it' do
    create(:trip, user:, started_at: Time.utc(2026, 10, 1), ended_at: candidate.started_at - 1.second)
    expect(created.size).to eq(1)
  end

  it 'yields to a dismissed period' do
    create(:trip, user:, origin: :detected, started_at: candidate.started_at, ended_at: candidate.ended_at)
      .destroy_by_user!
    expect(created).to be_empty
  end

  it 'replaces an untouched Detected Trip whose period moved' do
    old = create(:trip, user:, origin: :detected, started_at: Time.utc(2026, 10, 10, 8),
                        ended_at: Time.utc(2026, 10, 13, 20))
    expect(created.size).to eq(1)
    expect(Trip.exists?(old.id)).to be(false)
    expect(user.trip_detection_dismissals).to be_empty
  end

  it 'never changes an edited Detected Trip, and yields to it' do
    edited = create(:trip, user:, origin: :detected, user_edited_at: Time.current,
                           started_at: Time.utc(2026, 10, 10, 8), ended_at: Time.utc(2026, 10, 13, 20))
    expect(created).to be_empty
    expect(edited.reload.ended_at).to eq(Time.utc(2026, 10, 13, 20))
  end

  it 'yields to a dismissed period that overlaps only part of the period' do
    create(:trip, user:, origin: :detected, started_at: Time.utc(2026, 10, 13), ended_at: Time.utc(2026, 10, 18))
      .destroy_by_user!
    expect(created).to be_empty
  end

  it 'neither removes nor renames a Detected Trip with a note' do
    noted = create(:trip, user:, origin: :detected, name: 'Old name',
                          started_at: candidate.started_at, ended_at: candidate.ended_at)
    stale = create(:trip, user:, origin: :detected, name: 'Kept')
    [noted, stale].each { |trip| create(:note, user:, attachable: trip, noted_at: trip.started_at + 1.hour) }
    Trip.where(id: [noted.id, stale.id]).update_all(user_edited_at: nil) # the note alone must hold them

    expect(created).to be_empty
    expect(noted.reload.name).to eq('Old name')
    expect(Trip.exists?(stale.id)).to be(true)
  end

  # Ruling R21
  it 'keeps a trip the user annotates while the run is under way' do
    stale = create(:trip, user:, origin: :detected, name: 'Kept')

    during_the_run(-> { create(:note, user:, attachable: stale, noted_at: stale.started_at + 1.hour) }) do
      described_class.new(user, []).call
    end

    expect(stale.reload.name).to eq('Kept')
  end

  it 'keeps the name a user gives a trip while the run is under way' do
    trip = create(:trip, user:, origin: :detected, name: 'Trip, 10–14 Oct 2026',
                         started_at: candidate.started_at, ended_at: candidate.ended_at)
    point_at(Time.utc(2026, 10, 11, 12), city: 'Lisbon', country: 'Portugal')

    user_edit = -> { Trip.where(id: trip.id).update_all(name: 'Our honeymoon', user_edited_at: Time.current) }
    during_the_run(user_edit) do
      expect(described_class.new(user, [candidate]).call).to be_empty
    end

    expect(trip.reload.name).to eq('Our honeymoon')
  end

  it 'creates nothing over a trip the user annotates while the run is under way' do
    stale = create(:trip, user:, origin: :detected, started_at: Time.utc(2026, 10, 10, 8),
                          ended_at: Time.utc(2026, 10, 13, 20))

    during_the_run(-> { create(:note, user:, attachable: stale, noted_at: stale.started_at + 1.hour) }) do
      expect(created).to be_empty
    end

    expect(user.trips.pluck(:id)).to eq([stale.id])
  end

  it 'never removes a Detected Trip with a share link' do
    shared = create(:trip, user:, origin: :detected)
    create(:shared_link, user:, resource_type: :trip, resource_id: shared.id)
    described_class.new(user, []).call
    expect(Trip.exists?(shared.id)).to be(true)
  end

  it 'removes an untouched Detected Trip that detection no longer produces' do
    stale = create(:trip, user:, origin: :detected)
    described_class.new(user, []).call
    expect(Trip.exists?(stale.id)).to be(false)
    expect(user.trip_detection_dismissals).to be_empty
  end

  it 'never removes a manual trip' do
    manual = create(:trip, user:)
    described_class.new(user, []).call
    expect(Trip.exists?(manual.id)).to be(true)
  end

  context 'with a Lite user' do
    let(:user) { create(:user, plan: :lite, skip_auto_trial: true, settings: { 'timezone' => 'Europe/Berlin' }) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'leaves Detected Trips outside the Lite window alone' do
      expect(user.plan_restricted?).to be(true)
      old = create(:trip, user:, origin: :detected, started_at: 2.years.ago - 3.days, ended_at: 2.years.ago)
      recent = create(:trip, user:, origin: :detected, started_at: 2.months.ago - 3.days, ended_at: 2.months.ago)

      described_class.new(user, []).call

      expect(Trip.exists?(old.id)).to be(true)
      expect(Trip.exists?(recent.id)).to be(false)
    end

    # Ruling R19
    it 'keeps a trip that began before the window, and drops the truncated period inside it' do
      window_start = user.data_window_start
      straddling = create(:trip, user:, origin: :detected, started_at: window_start - 5.days,
                                 ended_at: window_start + 5.days)
      truncated = Trips::Detection::Candidates::Candidate.new(window_start + 1.hour, window_start + 5.days)

      2.times { expect(described_class.new(user, [truncated]).call).to be_empty }

      expect(user.trips.pluck(:id)).to eq([straddling.id])
      expect(straddling.reload).to have_attributes(started_at: window_start - 5.days, ended_at: window_start + 5.days)
    end

    it 'replaces an untouched trip inside the window whose period moved, as for Pro' do
      moved = create(:trip, user:, origin: :detected, started_at: 2.months.ago - 3.days, ended_at: 2.months.ago)
      period = Trips::Detection::Candidates::Candidate.new(2.months.ago - 3.days, 2.months.ago + 1.day)

      expect(described_class.new(user, [period]).call.size).to eq(1)
      expect(Trip.exists?(moved.id)).to be(false)
    end
  end

  # Review Focus 3
  it 'renames an untouched trip that still has its fallback name once places are known' do
    trip = created.first # no city or country yet: fallback name
    expect(trip.name).to eq('Trip, 10–14 Oct 2026')
    point_at(Time.utc(2026, 10, 11, 12), city: 'Lisbon', country: 'Portugal')

    expect { described_class.new(user, [candidate]).call }.not_to have_enqueued_job(Trips::CalculateAllJob)
    expect(trip.reload.name).to eq('Lisbon, Oct 2026')
  end

  # Ruling R16
  it 'renames an untouched trip named after its country once its points get the city' do
    point = point_at(Time.utc(2026, 10, 11, 12), country: 'Portugal')
    trip = created.first
    expect(trip.name).to eq('Portugal, Oct 2026')

    point.update_columns(city: 'Lisbon')
    described_class.new(user, [candidate]).call

    expect(trip.reload.name).to eq('Lisbon, Oct 2026')
  end

  it 'never renames an edited Detected Trip' do
    edited = create(:trip, user:, origin: :detected, user_edited_at: Time.current, name: 'Our honeymoon',
                           started_at: candidate.started_at, ended_at: candidate.ended_at)
    point_at(Time.utc(2026, 10, 11, 12), city: 'Lisbon', country: 'Portugal')
    described_class.new(user, [candidate]).call
    expect(edited.reload.name).to eq('Our honeymoon')
  end
end
