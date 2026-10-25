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

  it 'exposes no position when the viewer has no points' do
    get map_v2_path

    expect(current_position_value).to be_nil
  end
end
