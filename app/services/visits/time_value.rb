# frozen_string_literal: true

module Visits
  module TimeValue
    module_function

    def parse(value)
      return nil if value.blank?

      year, month, day = Date._parse(value.to_s).values_at(:year, :mon, :mday)
      return nil if month && day && !Date.valid_date?(year || Time.zone.today.year, month, day)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
