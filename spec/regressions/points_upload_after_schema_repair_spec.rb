# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261102000100_ensure_points_source_id.rb')
require Rails.root.join('db/migrate/20261102000200_ensure_points_altitude_decimal.rb')

# Instances set up from the 1.5.0–1.6.x schema.rb never got
# points.altitude_decimal, and busy ones never got points.source_id. The 1.20
# points triggers read both, so app uploads returned 500 there until the
# upgrade adds the columns.
RSpec.describe 'Points upload after the points schema repair', type: :request do
  let(:connection) { ApplicationRecord.connection }
  let(:user) { create(:user) }

  # The payload the iOS and Android apps send to POST /api/v1/points.
  def app_batch(altitude)
    {
      locations: [0, 60].map do |offset|
        {
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [13.405 + (offset / 10_000.0), 52.52] },
          properties: {
            timestamp: Time.zone.parse('2026-11-02T12:00:00Z').advance(seconds: offset).iso8601,
            horizontal_accuracy: 8, vertical_accuracy: 3, altitude: altitude, speed: 1.2,
            course: 90, battery_level: 0.8, battery_state: 'unplugged', device_id: 'phone'
          }
        }
      end
    }
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    connection.execute('ALTER TABLE points DROP COLUMN altitude_decimal, DROP COLUMN source_id')
    Point.reset_column_information
    Points::DimensionResolver.reset_column_availability!

    EnsurePointsSourceId.new.up
    EnsurePointsAltitudeDecimal.new.up
    Points::DimensionResolver.reset_column_availability!
  end

  after do
    [Tracks::RealtimeDebouncer, Visits::RealtimeDebouncer].each { |debouncer| debouncer.new(user.id).clear }
    connection.execute('ALTER TABLE points ADD COLUMN IF NOT EXISTS altitude_decimal numeric(10,2), ' \
                       'ADD COLUMN IF NOT EXISTS source_id integer')
    Point.reset_column_information
    Points::DimensionResolver.reset_column_availability!
  end

  it 'stores a fresh batch from the app' do
    post api_v1_points_url(api_key: user.api_key), params: app_batch(35), as: :json

    expect(response).to have_http_status(:ok)
    expect(user.points.count).to eq(2)
  end

  it 'accepts the same batch again after a retry' do
    post api_v1_points_url(api_key: user.api_key), params: app_batch(35), as: :json
    post api_v1_points_url(api_key: user.api_key), params: app_batch(36), as: :json

    expect(response).to have_http_status(:ok)
    expect(user.points.pluck(:altitude)).to all(eq(36))
  end
end
