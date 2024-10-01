# frozen_string_literal: true

# By default, Geocoder supports only https protocol when talking to Photon API.
# This is kinda inconvenient when you're running a local instance of Photon
# and want to use http protocol. This monkey patch allows you to do that.

module Geocoder::Lookup
  class Photon < Base
    private

    def supported_protocols
      %i[https http]
    end
  end
end
