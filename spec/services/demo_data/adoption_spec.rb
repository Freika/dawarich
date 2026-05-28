# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Demo entity adoption', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    DemoData::Importer.new(user).call
  end

  it 'flips a demo visit to non-demo when the user confirms it' do
    visit = user.visits.demo.where(status: :suggested).first
    expect(visit).to be_present
    patch visit_path(visit), params: { visit: { status: 'confirmed' } }
    expect(visit.reload.demo).to be(false)
  end

  it 'flips a demo trip to non-demo when the user updates it' do
    trip = user.trips.demo.first
    expect(trip).to be_present
    patch trip_path(trip), params: { trip: { name: 'Edited' } }
    expect(trip.reload.demo).to be(false)
  end

  it 'flips a demo place to non-demo when the user updates it' do
    place = Place.demo.where(user_id: user.id).first
    expect(place).to be_present
    patch place_path(place), params: { place: { name: 'Edited place' } }
    expect(place.reload.demo).to be(false)
  end

  it 'flips a demo tag to non-demo when the user updates it' do
    tag = user.tags.demo.first
    expect(tag).to be_present
    patch tag_path(tag), params: { tag: { color: '#123456' } }
    expect(tag.reload.demo).to be(false)
  end

  it 'does NOT adopt on decline' do
    visit = user.visits.demo.where(status: :suggested).first
    expect(visit).to be_present
    patch visit_path(visit), params: { visit: { status: 'declined' } }
    expect(visit.reload.demo).to be(true)
  end
end
