# frozen_string_literal: true

module UserTimezone
  extend ActiveSupport::Concern

  private

  def with_user_timezone(user, &)
    Time.use_zone(Time.find_zone(user.timezone) || ENV.fetch('TIME_ZONE', 'UTC'), &)
  end
end
