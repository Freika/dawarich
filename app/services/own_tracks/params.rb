# frozen_string_literal: true

class OwnTracks::Params
  attr_reader :params

  def initialize(params)
    @params = params.to_h.deep_symbolize_keys
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  def call
    {
      lonlat: "POINT(#{params[:lon]} #{params[:lat]})",
      battery:            params[:batt],
      ping:               params[:p],
      altitude:           params[:alt],
      accuracy:           params[:acc],
      vertical_accuracy:  params[:vac],
      velocity:           speed,
      ssid:               params[:SSID],
      bssid:              params[:BSSID],
      tracker_id:         params[:tid],
      timestamp:          params[:tst].to_i,
      inrids:             params[:inrids],
      in_regions:         params[:inregions],
      topic:              params[:topic],
      battery_status:,
      connection:,
      trigger:,
      raw_data:           params.deep_stringify_keys
    }
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  private

  def battery_status
    return 'unknown' if params[:bs].nil?

    case params[:bs].to_i
    when 1 then 'unplugged'
    when 2 then 'charging'
    when 3 then 'full'
    else 'unknown'
    end
  end

  def trigger
    return 'unknown' if params[:t].nil?

    case params[:t]
    when 'p' then 'background_event'
    when 'c' then 'circular_region_event'
    when 'b' then 'beacon_event'
    when 'r' then 'report_location_message_event'
    when 'u' then 'manual_event'
    when 't' then 'timer_based_event'
    when 'v' then 'settings_monitoring_event'
    else 'unknown'
    end
  end

  def connection
    return 'mobile' if params[:conn].nil?

    case params[:conn]
    when 'm' then 'mobile'
    when 'w' then 'wifi'
    when 'o' then 'offline'
    else 'unknown'
    end
  end

  def speed
    return params[:vel] unless owntracks_point?

    # OwnTracks speed is in km/h, so we need to convert it to m/s
    # Reference: https://owntracks.org/booklet/tech/json/
    ((params[:vel].to_f * 1000) / 3600).round(1).to_s
  end

  def owntracks_point?
    params[:topic].present?
  end
end
