# frozen_string_literal: true

require 'rails_helper'

# The mobile apps upload through POST /api/v1/points with the payload below.
RSpec.describe 'Points API without altitude_decimal', type: :request do
  let(:connection) { ApplicationRecord.connection }
  let(:user) { create(:user) }

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
    skip 'column absence regression only applies when the decimal migration did not finish' unless
      connection.column_exists?(:points, :altitude_decimal)

    allow(Point).to receive(:altitude_decimal_supported?).and_return(false)
    connection.remove_column(:points, :altitude_decimal)
    Point.reset_column_information
    %w[db/exploration_invalidation.sql db/achievement_collections_invalidation.sql].each do |path|
      connection.execute(File.read(Rails.root.join(path)))
    end
  end

  after do
    [Tracks::RealtimeDebouncer, Visits::RealtimeDebouncer].each { |debouncer| debouncer.new(user.id).clear }
    unless connection.column_exists?(:points, :altitude_decimal)
      connection.add_column(:points, :altitude_decimal, :decimal, precision: 10, scale: 2)
      Point.reset_column_information
    end
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
