# frozen_string_literal: true

class SharedLocationChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_share.nil?
    return reject unless params[:share_id].to_s == current_share.id.to_s

    # The magic phrase is only verified when the connection is opened. The
    # share id does not change when the owner regenerates the phrase, so an
    # already-open socket would keep streaming unless delivery re-checks that
    # the phrase this connection unlocked with is still the current one.
    stream_for current_share, coder: ActiveSupport::JSON do |message|
      # The revoke notice is broadcast after the phrase changes, so it must be
      # let through (the viewer shows "ended" and unsubscribes on it) before the
      # streams are stopped.
      next transmit_and_stop(message) if revoked?(message)
      next stop_all_streams unless share_still_unlocked?

      transmit message
    end
  end

  private

  def revoked?(message)
    message.is_a?(Hash) && (message['revoked'] || message[:revoked])
  end

  def transmit_and_stop(message)
    transmit message
    stop_all_streams
  end

  def share_still_unlocked?
    fresh = SharedLink.active.find_by(id: current_share.id)
    fresh.present? && fresh.magic_phrase.to_s == current_share.magic_phrase.to_s
  end
end
