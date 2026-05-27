# frozen_string_literal: true

module Imports
  class NoImportableDataError < StandardError
    DEFAULT_MESSAGE = 'No importable locations were found in this file. Dawarich puts timestamped ' \
                      'points on your timeline and untimed waypoints in your places; this file ' \
                      'contained neither.'

    def initialize(message = DEFAULT_MESSAGE)
      super
    end
  end
end
