# frozen_string_literal: true

class Visits::RealtimeDebouncer
  DEBOUNCE_DELAY = 5.minutes
  KEY_TTL = 10.minutes
  # Clusters that match an existing visit never claim their points, so every run
  # re-detects and re-names them. Now that the key is released each run, keep the
  # window tight — BulkVisitsSuggestingJob still re-scans the whole previous day.
  LOOKBACK_WINDOW = 6.hours

  def initialize(user_id)
    @user_id = user_id
  end

  def trigger
    return unless Geocoding::Config.for(@user_id).enabled?
    return unless user_opted_in?

    return unless PhoenixClaims.debounce(key, KEY_TTL.to_i)

    begin
      VisitSuggestingJob
        .set(wait: DEBOUNCE_DELAY)
        .perform_later(user_id: @user_id, start_at: LOOKBACK_WINDOW.ago.iso8601, end_at: Time.current.iso8601)
    rescue StandardError
      PhoenixClaims.unclaim(key)
      raise
    end
  end

  def clear = PhoenixClaims.unclaim(key)

  private

  def user_opted_in?
    User.find_by(id: @user_id)&.safe_settings&.visits_suggestions_enabled?
  end

  def key
    "visit_realtime:user:#{@user_id}"
  end
end
