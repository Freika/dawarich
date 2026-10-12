# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TrackBuilder under concurrent creation', :non_transactional, threads: 8 do
  let(:user) { create(:user) }

  let(:host_class) do
    Class.new do
      include Tracks::TrackBuilder
      attr_reader :user

      def initialize(user)
        @user = user
      end
    end
  end

  def build_points(user, count: 10)
    base = Time.zone.parse('2026-04-01 10:00:00').to_i
    Array.new(count) do |i|
      create(
        :point,
        user: user,
        timestamp: base + i,
        latitude: 52.5 + (i * 0.0001),
        longitude: 13.4 + (i * 0.0001),
        altitude: 50 + i,
        track_id: nil
      )
    end
  end

  it 'produces exactly one track and reuses it across racing threads' do
    points = build_points(user)
    point_ids = points.map(&:id)

    start_latch = Concurrent::CountDownLatch.new(1)
    ready_latch = Concurrent::CountDownLatch.new(8)
    results = Concurrent::Array.new

    threads = Array.new(8) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          host = host_class.new(User.find(user.id))
          fresh_points = Point.where(id: point_ids).order(:timestamp).to_a
          ready_latch.count_down
          start_latch.wait
          track = host.create_track_from_points(fresh_points, 1000.0)
          results << track&.id
        end
      end
    end

    Timeout.timeout(10) { ready_latch.wait }
    start_latch.count_down
    threads.each { |t| t.join(20) }

    track_count = Track.where(
      user_id: user.id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp)
    ).count

    expect(track_count).to eq(1)

    winner_id = Track.where(user_id: user.id).pick(:id)
    non_nil_results = results.compact
    expect(non_nil_results).not_to be_empty
    expect(non_nil_results.uniq).to eq([winner_id])

    expect(Point.where(id: point_ids).pluck(:track_id).uniq).to eq([winner_id])
  end
end
