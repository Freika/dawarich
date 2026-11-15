# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip route queries disable PostgreSQL JIT' do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC', 'minutes_between_routes' => 60 }) }
  let(:started_at) { Time.utc(2026, 1, 1) }
  let(:trip) do
    create(:trip, user:, started_at:, ended_at: started_at + 2.days, path: nil,
                  skip_calculation_enqueue: true)
  end

  before do
    trip
    # Synthetic routes in the South Pacific, away from inhabited places.
    2.times do |day|
      start = started_at + day.days + 10.hours
      track = create(:track, user:, tracker_id: 'synthetic-phone', start_at: start, end_at: start + 10.minutes,
                             original_path: 'LINESTRING(-140.02 -40, -140.03 -40)')
      [-140.02, -140.03].each_with_index do |longitude, index|
        create(:point, user:, track:, tracker_id: 'synthetic-phone', timestamp: (start + index * 10.minutes).to_i,
                       lonlat: "POINT(#{longitude} -40)")
      end
    end
  end

  %i[call feature_rows].each do |operation|
    it "runs #{operation} with JIT off even when the connection has JIT enabled" do
      # Tile 5/3/19 covers the synthetic routes on both days.
      query = Trips::RoutesTileQuery.new(trip:, z: 5, x: 3, y: 19, timezone: 'UTC',
                                         points_scope: trip.primary_device_points)
      connection = Point.connection
      observed_jit = []
      collector = lambda do |*args|
        sql = args.last[:sql]
        observed_jit << connection.select_value('SHOW jit') if sql.start_with?('WITH candidates AS MATERIALIZED')
      end
      result = nil

      connection.transaction(requires_new: true) do
        connection.execute('SET LOCAL jit = on')
        ActiveSupport::Notifications.subscribed(collector, 'sql.active_record') do
          result = query.public_send(operation)
        end
        raise ActiveRecord::Rollback
      end

      feature_count = operation == :call ? result.feature_count : result.size
      expect(feature_count).to eq(2)
      expect(observed_jit).to eq(['off'])
    end
  end
end
