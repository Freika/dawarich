# frozen_string_literal: true

module FitFixtureHelper
  def generate_reader_fit_fixture(path, base, extra = '')
    require 'fit4ruby'
    source = File.binread(base)
    header_size = source.getbyte(0)
    data_size = source.byteslice(4, 4).unpack1('V')
    data = source.byteslice(header_size, data_size) + extra
    header = "#{[14, 32, 1012, data.bytesize].pack('CCvV')}.FIT"
    crc = Object.new.extend(Fit4Ruby::CRC16)
    header += [crc.compute_crc(StringIO.new(header), 0, header.bytesize)].pack('v')
    File.binwrite(path, header + data + [crc.compute_crc(StringIO.new(data), 0, data.bytesize)].pack('v'))
  end

  # Generates a FIT fixture where sessions may have no laps and all
  # trackpoint records are stored flat on the activity object.
  # Observed with FIT files exported from Garmin Connect.
  def generate_flat_record_fit_fixture(path)
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

  def generate_fit_fixture(path, include_device_info: true)
    require 'fit4ruby'

    ts = Time.utc(2024, 6, 15, 10, 30, 0)
    a = Fit4Ruby::Activity.new
    a.total_timer_time = 180.0
    if include_device_info
      a.new_device_info({ timestamp: ts, device_index: 0, manufacturer: 'garmin',
                          garmin_product: 'fenix3', serial_number: 123_456_789 })
    end
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

  def generate_fit_fixture_without_device_info(path)
    generate_fit_fixture(path, include_device_info: false)
  end
end

RSpec.configure do |config|
  config.include FitFixtureHelper
end
