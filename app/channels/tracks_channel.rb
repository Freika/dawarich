# frozen_string_literal: true

class TracksChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
