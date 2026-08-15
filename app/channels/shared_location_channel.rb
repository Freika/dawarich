# frozen_string_literal: true

class SharedLocationChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_share.nil?
    return reject unless params[:share_id].to_s == current_share.id.to_s

    stream_for current_share
  end
end
