# frozen_string_literal: true

class VideoExportsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
