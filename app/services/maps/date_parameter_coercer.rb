# frozen_string_literal: true

module Maps
  class DateParameterCoercer
    class InvalidDateFormatError < StandardError; end

    def self.call(param)
      new(param).call
    end

    def initialize(param)
      @param = param
    end

    def call
      coerce_date(@param)
    end

    private

    attr_reader :param

    def coerce_date(param)
      case param
      when String
        # Check if it's a numeric string (timestamp) or date string
        if param.match?(/^\d+$/)
          param.to_i
        else
          Time.parse(param).to_i
        end
      when Integer
        param
      else
        param.to_i
      end
    rescue ArgumentError => e
      Rails.logger.error "Invalid date format: #{param} - #{e.message}"
      raise InvalidDateFormatError, "Invalid date format: #{param}"
    end
  end
end
