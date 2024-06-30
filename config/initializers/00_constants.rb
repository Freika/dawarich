# frozen_string_literal: true

MIN_MINUTES_SPENT_IN_CITY = ENV.fetch('MIN_MINUTES_SPENT_IN_CITY', 60).to_i
REVERSE_GEOCODING_ENABLED = ENV.fetch('REVERSE_GEOCODING_ENABLED', 'true') == 'true'
