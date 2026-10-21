# frozen_string_literal: true

module Swarm
  module Checkins
    Checkin = Data.define(:id, :time, :latitude, :longitude, :venue_id, :venue_name)

    UTC = ActiveSupport::TimeZone['UTC']

    def self.parse(json)
      items = json.is_a?(Hash) ? json['items'] : nil
      return [] unless items.is_a?(Array)

      items.filter_map { |item| build(item) }.sort_by(&:time)
    end

    def self.build(item)
      return nil unless item.is_a?(Hash)

      latitude = item['lat']
      longitude = item['lng']
      return nil unless latitude.is_a?(Numeric) && longitude.is_a?(Numeric)
      return nil if latitude.zero? && longitude.zero?

      time = parse_time(item['createdAt'])
      return nil if time.nil?

      venue = item['venue'].is_a?(Hash) ? item['venue'] : {}

      Checkin.new(
        id: item['id'],
        time: time,
        latitude: latitude.to_f,
        longitude: longitude.to_f,
        venue_id: venue['id'].presence,
        venue_name: venue['name'].presence
      )
    end

    def self.parse_time(value)
      return Time.zone.at(value) if value.is_a?(Numeric)
      return nil unless value.is_a?(String) && value.present?

      UTC.parse(value)&.in_time_zone
    rescue ArgumentError
      nil
    end

    private_class_method :build, :parse_time
  end
end
