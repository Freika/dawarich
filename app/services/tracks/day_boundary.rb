# frozen_string_literal: true

# Local midnight in the user's timezone, when the user splits tracks there.
class Tracks::DayBoundary
  attr_reader :timezone

  def initialize(user)
    @timezone = user.timezone_iana if user.safe_settings.split_tracks_at_midnight?
    @zone = ActiveSupport::TimeZone[@timezone] if @timezone
  end

  def crosses?(from, to)
    return false unless @zone

    @zone.at(from.to_i).to_date != @zone.at(to.to_i).to_date
  end
end
