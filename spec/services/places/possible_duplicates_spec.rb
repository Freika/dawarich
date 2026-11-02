# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places::PossibleDuplicates' do
  let(:user) { create(:user) }

  def place_at(longitude, **attributes)
    create(:place, user:, latitude: 0, longitude:, visit_radius: 100, source: :photon, **attributes)
  end

  it 'finds overlapping circles even when neither center is inside the other radius' do
    first = place_at(0)
    second = place_at(0.0015)

    cluster = Places::PossibleDuplicates.new(user:).call.sole
    expect(cluster.places).to contain_exactly(first, second)
    expect(cluster.distances[second.id]).to be_within(2).of(167)
  end

  it 'joins an overlapping chain into one connected cluster' do
    chain = [0, 0.0015, 0.003].map { |longitude| place_at(longitude) }

    expect(Places::PossibleDuplicates.new(user:).call.sole.places).to match_array(chain)
  end

  it 'excludes isolated places and other users even when they would bridge a cluster' do
    place_at(0)
    place_at(0.003)
    place_at(0.0015, user: create(:user))

    expect(Places::PossibleDuplicates.new(user:).call).to be_empty
  end

  it 'excludes archived places on either side of a duplicate pair' do
    archived_first = place_at(0, archived: true)
    first = place_at(0.001)
    second = place_at(0.002)
    archived_last = place_at(0.003, archived: true)

    clusters = Places::PossibleDuplicates.new(user:).call

    expect(clusters.sole.places).to contain_exactly(first, second)
    expect(clusters.sole.distances.keys).not_to include(archived_first.id, archived_last.id)
  end

  it 'prefers a manual, name-locked or confirmed place over an older discovered place' do
    old = place_at(0, created_at: 2.years.ago)
    chosen = place_at(0.0015, source: :manual)
    expect(Places::PossibleDuplicates.new(user:).call.sole.survivor).to eq(chosen)
    chosen.update!(source: :photon, name_locked_at: Time.current)
    expect(Places::PossibleDuplicates.new(user:).call.sole.survivor).to eq(chosen)
    chosen.update!(name_locked_at: nil)
    create(:visit, user:, place: chosen, status: :confirmed)
    expect(Places::PossibleDuplicates.new(user:).call.sole.survivor).to eq(chosen)
    expect(old.reload).to be_photon
  end

  it 'pairs a small place with a much larger one whose radius covers it' do
    large = place_at(0, visit_radius: 2000)
    small = place_at(0.015, visit_radius: 20)

    expect(Places::PossibleDuplicates.new(user:).call.sole.places).to contain_exactly(large, small)
  end

  it 'returns no clusters for a user without places' do
    expect(Places::PossibleDuplicates.new(user:).call).to eq([])
  end

  it 'prefers the oldest place when no member is curated' do
    older = place_at(0, created_at: 2.years.ago)
    place_at(0.0015)

    expect(Places::PossibleDuplicates.new(user:).call.sole.survivor).to eq(older)
  end
end
