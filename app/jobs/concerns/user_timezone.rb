# frozen_string_literal: true

module UserTimezone
  extend ActiveSupport::Concern

  private

  def with_user_timezone(user, &block)
    Time.use_zone(user.timezone, &block)
  rescue ArgumentError
    Time.use_zone('UTC', &block)
  end
end
