# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imported places are visible on the map' do
  let(:user) { create(:user) }

  it 'shows an imported waypoint that carries no tag and no confirmed visit' do
    place = create(:place, user: user, source: :gpx_waypoint, name: 'Cafe Riquet')

    expect(Place.map_visible(user)).to include(place)
  end

  it 'still hides a suggested photon place that nothing references' do
    place = create(:place, user: user, source: :photon, name: 'Suggested place')

    expect(Place.map_visible(user)).not_to include(place)
  end
end
