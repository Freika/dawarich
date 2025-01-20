# frozen_string_literal: true

class Points::Params
  attr_reader :data, :points

  def initialize(json)
    @data = json.with_indifferent_access
    @points = @data[:locations]
  end

  def call
    points.map do |point|
      next if point[:geometry].nil? || point.dig(:properties, :timestamp).nil?

      {
        latitude:           point[:geometry][:coordinates][1],
        longitude:          point[:geometry][:coordinates][0],
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
        raw_data:           point
      }
    end.compact
  end

  private

  def battery_level(level)
    value = (level.to_f * 100).to_i

    value.positive? ? value : nil
  end
end
