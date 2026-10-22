# frozen_string_literal: true

class MapEditsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    stream_for current_user
  end
end
