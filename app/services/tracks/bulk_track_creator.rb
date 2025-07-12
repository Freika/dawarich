# frozen_string_literal: true

module Tracks
  class BulkTrackCreator
    def initialize(start_at: nil, end_at: 1.day.ago.end_of_day, user_ids: [])
      @start_at = start_at&.to_datetime
      @end_at = end_at&.to_datetime
      @user_ids = user_ids
    end

    def call
      users.find_each do |user|
        next if user.tracked_points.empty?

        user_start_at = start_at || start_time(user)

        next unless user.tracked_points.where(timestamp: user_start_at.to_i..end_at.to_i).exists?

        Tracks::CreateJob.perform_later(
          user.id,
          start_at: user_start_at,
          end_at:,
          cleaning_strategy: :daily
        )
      end
    end

    private

    attr_reader :start_at, :end_at, :user_ids

    def users
      user_ids.any? ? User.active.where(id: user_ids) : User.active
    end

    def start_time(user)
      latest_track = user.tracks.order(end_at: :desc).first

      if latest_track
        latest_track.end_at
      else
        oldest_point = user.tracked_points.order(:timestamp).first
        oldest_point ? Time.zone.at(oldest_point.timestamp) : 1.day.ago.beginning_of_day
      end
    end
  end
end
