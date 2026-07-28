# frozen_string_literal: true

require 'fit4ruby'

module Fit4Ruby
  class HeartRateZones
    def check(_index); end
  end

  class DeviceInfo
    def check(_index); end
  end

  module ActivityWithoutDeviceInfo
    def check
      missing_device_info = device_infos.empty?
      device_infos << DeviceInfo.new({}) if missing_device_info

      super
    ensure
      device_infos.pop if missing_device_info
    end
  end

  Activity.prepend(ActivityWithoutDeviceInfo) unless Activity < ActivityWithoutDeviceInfo
end
