# frozen_string_literal: true

class ExportSerializer
  attr_reader :points, :user_email

  def initialize(points, user_email)
    @points = points
    @user_email = user_email
  end

  def call
    { user_email => { 'dawarich-export' => export_points } }.to_json
  end

  private

  def export_points
    points.in_groups_of(1000, false).flat_map do |group|
      group.map { |point| export_point(point) }
    end
  end

  def export_point(point)
    {
      lat:        point.lat,
      lon:        point.lon,
      bs:         battery_status(point),
      batt:       point.battery,
      p:          point.ping,
      alt:        point.altitude,
      acc:        point.accuracy,
      vac:        point.vertical_accuracy,
      vel:        point.velocity,
      conn:       connection(point),
      SSID:       point.ssid,
      BSSID:      point.bssid,
      m:          trigger(point),
      tid:        point.tracker_id,
      tst:        point.timestamp.to_i,
      inrids:     point.inrids,
      inregions:  point.in_regions,
      topic:      point.topic,
      raw_data:   point.raw_data
    }
  end

  def battery_status(point)
    case point.battery_status
    when 'unplugged' then 'u'
    when 'charging' then 'c'
    when 'full' then 'f'
    else 'unknown'
    end
  end

  def trigger(point)
    case point.trigger
    when 'background_event' then 'p'
    when 'circular_region_event' then 'c'
    when 'beacon_event' then 'b'
    when 'report_location_message_event' then 'r'
    when 'manual_event' then 'u'
    when 'timer_based_event' then 't'
    when 'settings_monitoring_event' then 'v'
    else 'unknown'
    end
  end

  def connection(point)
    case point.connection
    when 'mobile' then 'm'
    when 'wifi' then 'w'
    when 'offline' then 'o'
    else 'unknown'
    end
  end
end
