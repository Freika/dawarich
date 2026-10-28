# frozen_string_literal: true

module Achievements
  class LocationTimezone
    def self.call(latitude, longitude)
      zones = TZF.raw_tz_names(latitude.to_f, longitude.to_f)
      return unless zones.one?

      TZInfo::Timezone.get(zones.first).identifier
    rescue TZF::InvalidCoordinatesError, TZInfo::InvalidTimezoneIdentifier
      nil
    end

    def self.version
      "tzf2-#{TZF::VERSION}/#{TZF.engine_version}/#{TZF.data_version}"
    end
  end
end
