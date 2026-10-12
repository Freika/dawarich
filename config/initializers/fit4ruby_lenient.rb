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

  module FieldDescriptionEntityCoercion
    def full_field_name(developer_data_ids)
      developer_data_ids =
        if developer_data_ids.respond_to?(:top_level_record)
          developer_data_ids.top_level_record&.developer_data_ids || []
        elsif developer_data_ids.respond_to?(:developer_data_ids)
          developer_data_ids.developer_data_ids
        else
          developer_data_ids
        end

      super(developer_data_ids)
    end
  end

  FieldDescription.prepend(FieldDescriptionEntityCoercion) unless FieldDescription < FieldDescriptionEntityCoercion
end
