# frozen_string_literal: true

module Stats
  class RecalculationDebouncer
    DEBOUNCE_DELAY = 1.minute
    KEY_TTL = 5.minutes

    def initialize(user_id)
      @user_id = user_id
    end

    def trigger
      return unless PhoenixClaims.debounce(key, KEY_TTL.to_i)

      Stats::FullRecalculationJob.set(wait: DEBOUNCE_DELAY).perform_later(@user_id)
    end

    def clear = PhoenixClaims.unclaim(key)

    private

    def key
      "stats_full_recalculation:user:#{@user_id}"
    end
  end
end
