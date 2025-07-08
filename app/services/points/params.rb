# frozen_string_literal: true

class Points::Params
  attr_reader :data, :points, :user_id

  def initialize(json, user_id)
    @data = json.with_indifferent_access
    @points = @data[:locations]
    @user_id = user_id
  end

  def call
    points.map do |point|
      next unless params_valid?(point)

      {
        lonlat: lonlat(point),
        battery_status:     point[:properties][:battery_state],
        battery:            battery_level(point[:properties][:battery_level]),
        timestamp:          DateTime.parse(point[:properties][:timestamp]),
        altitude:           point[:properties][:altitude],
        tracker_id:         point[:properties][:device_id],
        velocity:           point[:properties][:speed],
        ssid:               point[:properties][:wifi],
        accuracy:           point[:properties][:horizontal_accuracy],
        vertical_accuracy:  point[:properties][:vertical_accuracy],
        course_accuracy:    point[:properties][:course_accuracy],
        course:             point[:properties][:course],
        raw_data:           point,
        user_id:            user_id
      }
    end.compact
  end

  private

  def battery_level(level)
    value = (level.to_f * 100).to_i

    value.positive? ? value : nil
  end

  def params_valid?(point)
    point.dig(:geometry, :coordinates).present? &&
      point.dig(:properties, :timestamp).present?
  end

  def lonlat(point)
    "POINT(#{point[:geometry][:coordinates][0]} #{point[:geometry][:coordinates][1]})"
  end
end
