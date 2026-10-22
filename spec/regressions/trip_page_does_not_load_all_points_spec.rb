# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip page does not load all points', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:trip) do
    create(:trip, user:, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 3),
                  skip_calculation_enqueue: true)
  end

  before do
    sign_in user
    times = (0..5).map { |step| Time.utc(2026, 1, 1, 10, step * 5) }
    longitudes = (0..5).map { |step| -140.02 - (step * 0.001) }
    track = create(:track, user:, tracker_id: 'phone', start_at: times.first, end_at: times.last,
                           original_path: "LINESTRING(#{longitudes.map { |lon| "#{lon} -40" }.join(', ')})")
    times.zip(longitudes).each do |time, longitude|
      create(:point, user:, track:, tracker_id: 'phone', timestamp: time.to_i, lonlat: "POINT(#{longitude} -40)")
    end
    vertices = Array.new(20_000) { |i| format('%.5f -40.00000', -150 + (i * 0.0005)) }
    trip.update_columns(path: "LINESTRING(#{vertices.join(', ')})")
  end

  def tile_path(template, zoom)
    n = 2**zoom
    lat = -40 * Math::PI / 180
    x = ((-140.02 + 180) / 360 * n).floor
    y = ((1 - (Math.log(Math.tan(lat) + (1 / Math.cos(lat))) / Math::PI)) / 2 * n).floor
    template.sub('{z}', zoom.to_s).sub('{x}', x.to_s).sub('{y}', y.to_s)
  end

  it 'renders the route from tiles the page points at instead of embedding the path' do
    get trip_path(trip)

    expect(response.body).not_to include('-144.9995')

    template = Nokogiri::HTML(response.body).at_css('[data-controller="trip-maplibre"]')['data-trip-maplibre-tiles-url-value']
    get tile_path(template, 12), headers: { 'Authorization' => "Bearer #{user.api_key}" }

    expect(response).to have_http_status(:ok)
    expect(response.body.b).to include('trip_routes'.b)
  end
end
