# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 route gap settings', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'allows route gap values above the former slider limits' do
    get map_v2_path

    document = Nokogiri::HTML(response.body)
    meters = document.at_css('input[name="metersBetweenRoutes"]')
    minutes = document.at_css('input[name="minutesBetweenRoutes"]')

    expect(meters['type']).to eq('number')
    expect(meters['min']).to eq('1')
    expect(meters['step']).to eq('1')
    expect(meters).not_to have_attribute('max')
    expect(meters).to have_attribute('required')
    expect(minutes['type']).to eq('number')
    expect(minutes['min']).to eq('1')
    expect(minutes['max']).to eq('1440')
    expect(minutes['step']).to eq('1')
    expect(minutes).to have_attribute('required')
  end

  it 'passes saved route gaps to trip maps' do
    user.settings['meters_between_routes'] = '10000'
    user.settings['minutes_between_routes'] = '240'
    user.save!
    trip = create(:trip, user:)
    allow_any_instance_of(Trip).to receive(:photos_by_day).and_return({})

    get trip_path(trip)

    root = Nokogiri::HTML(response.body).at_css('[data-controller="trip-maplibre"]')
    expect(root['data-trip-maplibre-meters-between-routes-value']).to eq('10000')
    expect(root['data-trip-maplibre-minutes-between-routes-value']).to eq('240')
  end
end
