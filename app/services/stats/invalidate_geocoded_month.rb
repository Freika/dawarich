# frozen_string_literal: true

class Stats::InvalidateGeocodedMonth
  def self.call(point)
    date = Time.at(point.timestamp).in_time_zone(point.user.timezone_iana)
    Stat.transaction do
      stat = Stat.find_or_create_by!(user_id: point.user_id, year: date.year, month: date.month) do |record|
        record.distance = 0
      end
      stat.lock!
      stat.update_columns(calculation_version: 0) unless stat.calculation_version.zero?
    end
  end
end
