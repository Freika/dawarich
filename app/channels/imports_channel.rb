# frozen_string_literal: true

class ImportsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
