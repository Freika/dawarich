# frozen_string_literal: true

class Tracks::RealtimeDebouncer
  DEBOUNCE_DELAY = 45.seconds
  KEY_TTL = 2.minutes

  def initialize(user_id)
    @user_id = user_id
  end

  def trigger
    return unless PhoenixClaims.debounce(key, KEY_TTL.to_i)

    Tracks::RealtimeGenerationJob.set(wait: DEBOUNCE_DELAY).perform_later(@user_id)
  end

  def clear = PhoenixClaims.unclaim(key)

  private

  def key
    "track_realtime:user:#{@user_id}"
  end
end
