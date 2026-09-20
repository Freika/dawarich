# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Chunk orphan claims under concurrency', :non_transactional, threads: 2 do
  let(:user) { create(:user) }
  let(:builder_class) do
    Class.new do
      include Tracks::TrackBuilder
      attr_reader :user

      def initialize(user)
        @user = user
      end
    end
  end

  it 'claims overlapping stale snapshots without empty tracks or inaccurate bounds' do
    points = 13.times.map do |index|
      create(:point, user: user, timestamp: Time.utc(2026, 1, 14).to_i + index * 60,
                     latitude: 40 + index * 0.001, longitude: 0)
    end
    ready = Concurrent::CountDownLatch.new(2)
    start = Concurrent::CountDownLatch.new(1)
    threads = [points.first(9), points].map do |snapshot|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          builder = builder_class.new(User.find(user.id))
          ready.count_down
          start.wait
          builder.create_track_from_points(snapshot, 999_999, orphan_only: true)
        end
      end
    end

    expect(ready.wait(5)).to be(true)
    start.count_down
    Timeout.timeout(15) { threads.each(&:value) }

    expect(user.points.where(track_id: nil)).not_to exist
    user.tracks.each do |track|
      members = track.points.order(:timestamp).to_a
      expect(members.size).to be >= 2
      expect(track.start_at.to_i).to eq(members.first.timestamp)
      expect(track.end_at.to_i).to eq(members.last.timestamp)
      expect(track.distance).to eq(Point.calculate_distance_for_array_geocoder(members, :m).round)
    end
  ensure
    start&.count_down
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end
end
