# frozen_string_literal: true

class TracksSerializer
  def initialize(user, track_ids)
    @user = user
    @track_ids = track_ids
  end

  def call
    return [] if track_ids.empty?

    tracks = user.tracks
                 .where(id: track_ids)
                 .order(start_at: :asc)

    tracks.map { |track| TrackSerializer.new(track).call }
  end

  private

  attr_reader :user, :track_ids
end
