# frozen_string_literal: true

class OwnTracks::Params
  attr_reader :params

  def initialize(params)
    @params = params.to_h.deep_symbolize_keys
  end

  def call
    {
      latitude: params[:lat],
      longitude: params[:lon],
      battery_status: battery_status,
      battery: params[:batt],
      ping: params[:p],
      altitude: params[:alt],
      accuracy: params[:acc],
      vertical_accuracy: params[:vac],
      velocity: params[:vel],
      connection: connection,
      ssid: params[:SSID],
      bssid: params[:BSSID],
      trigger: trigger,
      tracker_id: params[:tid],
      timestamp: params[:tst].to_i,
      inrids: params[:inrids],
      in_regions: params[:inregions],
      topic: params[:topic],
      raw_data: params.deep_stringify_keys
    }
  end

  private

  def battery_status
    return 'unknown' if params[:bs].nil?

    case params[:bs]
    when 'u' then 'unplugged'
    when 'c' then 'charging'
    when 'f' then 'full'
    else 'unknown'
    end
  end

  def trigger
    return 'unknown' if params[:m].nil?

    case params[:m]
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
end
