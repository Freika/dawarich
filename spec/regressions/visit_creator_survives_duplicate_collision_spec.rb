# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit creation survives a unique-index collision' do
  let(:user) { create(:user) }
  let(:place) { create(:place, user: user) }
  let(:started_at) { Time.zone.parse('2026-03-04 10:00:00') }

  let(:visit_data) do
    {
      start_time: started_at.to_i,
      end_time: (started_at + 1.hour).to_i,
      duration: 3600,
      suggested_name: 'Cafe',
      latitude: place.latitude,
      longitude: place.longitude,
      points: []
    }
  end

  it 'skips a colliding visit instead of aborting the whole batch' do
    create(:visit, user: user, place: place, started_at: started_at, ended_at: started_at + 1.hour)

    allow_any_instance_of(Visits::PlaceFinder).to receive(:find_or_create_place).and_return(place)
    allow_any_instance_of(Visits::Creator).to receive(:find_existing_visit).and_return(nil)

    creator = Visits::Creator.new(user)

    expect { creator.create_visits([visit_data]) }.not_to raise_error
    expect(user.visits.where(place_id: place.id, started_at: started_at).count).to eq(1)
  end

  it 'still creates the visits that do not collide' do
    other_place = create(:place, user: user)
    create(:visit, user: user, place: place, started_at: started_at, ended_at: started_at + 1.hour)

    allow_any_instance_of(Visits::Creator).to receive(:find_existing_visit).and_return(nil)
    allow_any_instance_of(Visits::PlaceFinder).to receive(:find_or_create_place)
      .and_return(place, other_place)

    second = visit_data.merge(start_time: (started_at + 5.hours).to_i,
                              end_time: (started_at + 6.hours).to_i)

    creator = Visits::Creator.new(user)
    result = creator.create_visits([visit_data, second])

    expect(result.compact.size).to eq(1)
  end
end
