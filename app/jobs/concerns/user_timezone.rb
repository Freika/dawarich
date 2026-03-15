# frozen_string_literal: true

module UserTimezone
  extend ActiveSupport::Concern

  private

  def with_user_timezone(user, &block)
    timezone = user.timezone
    Time.use_zone(timezone, &block)
  rescue ArgumentError
    fallback = ENV.fetch('TIME_ZONE', 'UTC')
    Time.use_zone(fallback, &block)
  end
end
