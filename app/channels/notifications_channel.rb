# frozen_string_literal: true

class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.nil?

    stream_for current_user
  end
end
