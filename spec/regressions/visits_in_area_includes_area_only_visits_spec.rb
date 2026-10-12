# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map Select Area returns visits attached only to an Area' do
  let(:user) { create(:user) }

  let(:envelope_params) do
    {
      sw_lat: '52.4', sw_lng: '13.5',
      ne_lat: '52.5', ne_lng: '13.6'
    }
  end

  let!(:area_inside) do
    create(:area, user: user, latitude: 52.437, longitude: 13.539, radius: 100)
  end

  let!(:area_outside) do
    create(:area, user: user, latitude: 50.0, longitude: 10.0, radius: 100)
  end

  let!(:place_inside) do
    create(:place, latitude: 52.450, longitude: 13.550)
  end

  let!(:area_only_visit) do
    create(:visit, user: user, area: area_inside, place: nil,
                   started_at: 2.hours.ago, ended_at: 1.hour.ago)
  end

  let!(:place_only_visit) do
    create(:visit, user: user, area: nil, place: place_inside,
                   started_at: 4.hours.ago, ended_at: 3.hours.ago)
  end

  let!(:visit_outside_envelope) do
    create(:visit, user: user, area: area_outside, place: nil,
                   started_at: 6.hours.ago, ended_at: 5.hours.ago)
  end

  subject(:result) { Visits::FindWithinBoundingBox.new(user, envelope_params).call }

  it 'includes visits whose Area centroid falls inside the envelope' do
    expect(result).to include(area_only_visit)
  end

  it 'still includes visits whose Place falls inside the envelope' do
    expect(result).to include(place_only_visit)
  end

  it 'excludes visits whose Area centroid falls outside the envelope' do
    expect(result).not_to include(visit_outside_envelope)
  end
end
