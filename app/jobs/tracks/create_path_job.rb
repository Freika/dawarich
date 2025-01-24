# frozen_string_literal: true

class Tracks::CreatePathJob < ApplicationJob
  queue_as :default

  def perform(track_id)
    track = Track.find(track_id)
    track.set_path

    track.save!
  end
end
