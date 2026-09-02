# frozen_string_literal: true

# Instance settings — values that belong to a whole deployment rather than to a
# user. See CONTEXT.md for the Instance setting / User setting / Pinned terms.
module InstanceSettings
  FLAG = :instance_settings_resolver
  # Short deliberately. This is a kill-switch: an operator turning it off during
  # an incident should not wait half a minute for every process to honour it.
  # 5s still collapses a bulk import's per-point reads from thousands to a
  # handful, which was the whole point of caching it.
  FLAG_TTL = 5.seconds

  class << self
    # Off means the ENV constants stay authoritative and nothing reads the
    # instance_settings table, which is the rollback path for the geocoding
    # rerouting this module enables.
    #
    # Cached deliberately. Flipper's memoizer is Rack middleware, so it does not
    # cover Sidekiq, and `Point` evaluates DawarichSettings.store_geodata? once
    # per created row — an uncached read here put two SELECTs on the hottest
    # write path in the app, with the flag off.
    def enabled?
      cached = @flag
      return cached[:value] if cached && cached[:at] > FLAG_TTL.ago

      value = read_flag
      @flag = { value: value, at: Time.current }.freeze
      value
    end

    def reset_flag_cache!
      @flag = nil
    end

    private

    def read_flag
      Flipper.enabled?(FLAG)
    rescue StandardError => e
      Rails.logger.warn("[InstanceSettings] flag unreadable (#{e.class}); treating as disabled")
      false
    end
  end
end
