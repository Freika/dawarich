# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Current position on the web map', type: :request do
  let(:viewer) { create(:user) }

  before do
    viewer.update!(settings: viewer.settings.merge('live_map_enabled' => false))
    sign_in viewer
  end

  def current_position_value
    Nokogiri::HTML(response.body)
            .at_css('#maps-maplibre-container')['data-maps--maplibre-current-position-value']
  end

  it 'exposes the viewer latest point to the map without live mode' do
    create(:point, user: viewer, lonlat: 'POINT(-140.04 -45.02)', timestamp: 20.minutes.ago.to_i)
    latest = create(:point, user: viewer, lonlat: 'POINT(-140.01 -45.005)', timestamp: 5.minutes.ago.to_i)
    create(:point, user: create(:user), lonlat: 'POINT(-139.0 -44.0)', timestamp: 1.minute.ago.to_i)

    get map_v2_path

    expect(JSON.parse(current_position_value)).to eq(
      'longitude' => latest.lon, 'latitude' => latest.lat, 'timestamp' => latest.timestamp
    )
  end

  it 'skips an anomalous latest point' do
    previous = create(:point, user: viewer, lonlat: 'POINT(-140.04 -45.02)', timestamp: 20.minutes.ago.to_i)
    create(:point, user: viewer, lonlat: 'POINT(-120.0 -30.0)', timestamp: 5.minutes.ago.to_i, anomaly: true)

    get map_v2_path

    expect(JSON.parse(current_position_value)).to include('longitude' => previous.lon, 'latitude' => previous.lat)
  end

  it 'hides the position while the latest point is inside a privacy zone' do
    tag = create(:tag, :privacy_zone, user: viewer, privacy_radius_meters: 500)
    home = create(:place, user: viewer, name: 'Home', latitude: -45.005, longitude: -140.01,
                          lonlat: 'POINT(-140.01 -45.005)')
    create(:tagging, tag: tag, taggable: home)
    create(:point, user: viewer, lonlat: 'POINT(-140.2 -45.2)', timestamp: 20.minutes.ago.to_i)
    create(:point, user: viewer, lonlat: 'POINT(-140.011 -45.005)', timestamp: 5.minutes.ago.to_i)

    get map_v2_path

    expect(current_position_value).to be_nil
  end

  it 'exposes no position when the viewer has no points' do
    get map_v2_path

    expect(current_position_value).to be_nil
  end
end
