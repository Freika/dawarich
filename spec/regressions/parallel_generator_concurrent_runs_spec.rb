# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ParallelGenerator under concurrent runs', :non_transactional, threads: 4 do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def seed_points(count: 30)
    base = Time.zone.parse('2026-04-01 09:00:00').to_i
    Array.new(count) do |i|
      create(
        :point,
        user: user,
        timestamp: base + (i * 30),
        latitude: 52.5 + (i * 0.0005),
        longitude: 13.4 + (i * 0.0005),
        altitude: 50,
        track_id: nil
      )
    end
  end

  def drain_track_jobs
    perform_enqueued_jobs(only: [Tracks::TimeChunkProcessorJob])
  end

  it 'produces no duplicate (user_id, start_at, end_at) triples under concurrent invocation' do
    seed_points

    range_start = Time.zone.parse('2026-04-01 08:00:00')
    range_end   = Time.zone.parse('2026-04-01 12:00:00')

    start_latch = Concurrent::CountDownLatch.new(1)
    ready_latch = Concurrent::CountDownLatch.new(2)

    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready_latch.count_down
          start_latch.wait
          Tracks::ParallelGenerator.new(
            User.find(user.id),
            start_at: range_start,
            end_at: range_end,
            mode: :daily
          ).call
        end
      end
    end

    Timeout.timeout(10) { ready_latch.wait }
    start_latch.count_down
    threads.each { |t| t.join(20) }

    drain_track_jobs

    duplicates = Track.where(user_id: user.id)
                      .group(:start_at, :end_at)
                      .having('COUNT(*) > 1')
                      .count

    expect(duplicates).to be_empty

    point_track_ids = Point.where(user_id: user.id).pluck(:track_id).compact
    expect(point_track_ids.size).to be > 0
    expect(point_track_ids.tally.values.all? { |c| c >= 1 }).to be true
  end
end
