# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::StateStore do
  it 'rebuilds state from surviving places only', :place_retention do
    user = create(:user)
    place = create(:place, :geofence, user:)
    create(:geofence_event, user:, place:)
    create(:geofence_event, user:, place: nil, place_name: 'Deleted place')
    store = described_class.new(user)
    store.reset!

    expect(store.inside_ids).to eq(Set[place.id])
  end
end
