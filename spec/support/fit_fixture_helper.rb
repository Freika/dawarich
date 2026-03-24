# frozen_string_literal: true

module FitFixtureHelper
  def generate_fit_fixture(path)
    require 'fit4ruby'

    ts = Time.utc(2024, 6, 15, 10, 30, 0)
    a = Fit4Ruby::Activity.new
    a.total_timer_time = 180.0
    a.new_device_info({ timestamp: ts, device_index: 0, manufacturer: 'garmin',
                        garmin_product: 'fenix3', serial_number: 123_456_789 })
    3.times do |i|
      a.new_record({ timestamp: ts + (i * 60), position_lat: 52.52 + i * 0.001,
                     position_long: 13.405 + i * 0.001, altitude: (34 + i).to_f,
                     speed: 5.0 + i * 0.5, heart_rate: 140 + i * 5,
                     cadence: 80 + i, distance: 100.0 * (i + 1) })
    end
    a.new_lap({ timestamp: ts + 180, sport: 'cycling', sub_sport: 'generic',
                message_index: 0, total_cycles: 100, start_time: ts,
                total_timer_time: 180.0, total_distance: 300.0,
                total_ascent: 2, total_descent: 0,
                avg_speed: 5.5, max_speed: 6.0,
                avg_heart_rate: 147, max_heart_rate: 150,
                avg_cadence: 81, max_cadence: 82 })
    a.new_session({ timestamp: ts + 180, sport: 'cycling', sub_sport: 'generic',
                    start_time: ts, total_timer_time: 180.0, total_elapsed_time: 180.0,
                    total_distance: 300.0, total_ascent: 2, total_descent: 0,
                    avg_speed: 5.5, max_speed: 6.0,
                    avg_heart_rate: 147, max_heart_rate: 150,
                    avg_cadence: 81, max_cadence: 82,
                    nec_lat: 52.522, nec_long: 13.407,
                    swc_lat: 52.520, swc_long: 13.405 })
    Fit4Ruby.write(path, a)
  end
end

RSpec.configure do |config|
  config.include FitFixtureHelper
end
