# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvent do
  it 'keeps synthetic test events out of the real scope' do
    real = create(:geofence_event)
    create(:geofence_event, user: real.user, place: real.place, synthetic: true)

    expect(described_class.real).to contain_exactly(real)
  end

  it 'requires an event type, source and times' do
    event = described_class.new

    expect(event).not_to be_valid
    expect(event.errors.attribute_names).to include(:event_type, :source, :occurred_at, :received_at)
  end

  it 'accepts an event without a place', :place_retention do
    event = build(:geofence_event, place: nil)

    expect(event).to be_valid
  end

  it 'displays the live place name ahead of its snapshot', :place_retention do
    event = create(:geofence_event, place_name: 'Old name')
    event.place.update!(name: 'Current name')

    expect(event.display_place_name).to eq('Current name')
  end

  it 'displays the snapshot after its place is gone', :place_retention do
    event = create(:geofence_event, place: nil, place_name: 'Former home')

    expect(event.reload.display_place_name).to eq('Former home')
  end
end
