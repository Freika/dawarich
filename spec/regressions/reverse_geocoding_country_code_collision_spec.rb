# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reverse geocoding country-code collisions' do
  let(:point) do
    create(:point).tap do |record|
      record.update_columns(country_id: nil, country_name: nil, city: nil)
    end
  end

  let(:united_states) do
    create(
      :country,
      name: 'United States of America',
      iso_a2: 'US',
      iso_a3: 'USA',
      geom: 'MULTIPOLYGON (((-125 25, -66 25, -66 49, -125 49, -125 25)))'
    )
  end

  before do
    Country.where(iso_a2: 'US').delete_all

    create(
      :country,
      name: 'US Naval Base Guantanamo Bay',
      iso_a2: 'US',
      iso_a3: 'USA',
      geom: 'MULTIPOLYGON (((-76 19, -75 19, -75 20, -76 20, -76 19)))'
    )
    united_states

    response = double(city: 'Savannah', country: 'United States', country_code: 'us', data: {})
    allow(Geocoding::Search).to receive(:call).and_return([response])
  end

  it 'links a US result to the canonical country record' do
    described_class = ReverseGeocoding::Points::FetchData

    expect { described_class.new(point.id).call }
      .to change { point.reload.country_id }.from(nil).to(united_states.id)
  end
end
