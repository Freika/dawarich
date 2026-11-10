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
