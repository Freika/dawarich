# frozen_string_literal: true

module Visits
  class InvalidTimeRange < StandardError
    def initialize(message = 'Invalid time range')
      super
    end
  end
end
