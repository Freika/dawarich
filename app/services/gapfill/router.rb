# frozen_string_literal: true

module Gapfill
  class Router
    class RoutingError < StandardError; end

    # Default modes: label => BRouter profile name.
    # Override with BROUTER_MODES env var as comma-separated label:profile pairs.
    # Example: BROUTER_MODES="Walk:hiking-mountain,Bike:trekking,Car:car-fast,Rail:rail"
    DEFAULT_MODES = {
      'Hiking' => 'hiking-mountain',
      'Trekking Bike' => 'trekking',
      'Fastbike' => 'fastbike',
      'Fastbike (low traffic)' => 'fastbike-verylowtraffic',
      'MTB' => 'mtb',
      'Gravel' => 'gravel',
      'Car' => 'car-vario',
      'Moped' => 'moped',
      'Rail' => 'rail',
      'River' => 'river',
      'Shortest' => 'shortest'
    }.freeze

    MAX_ALTERNATIVES = 3

    def initialize(brouter_url: ENV['BROUTER_URL'])
      @brouter_url = brouter_url
    end

    # Returns an Array of [lon, lat] pairs for a single route.
    # mode: one of the keys from self.modes (e.g. "Walk", "Car")
    # alternative: 0 = primary, 1-3 = alternatives
    def route(from:, to:, mode:, alternative: 0)
      profile = self.class.modes[mode]
      raise RoutingError, "unknown mode: #{mode}" unless profile

      idx = alternative.to_i.clamp(0, MAX_ALTERNATIVES)
      fetch_route(from, to, profile, idx)
    end

    # Returns the configured modes as { label => profile } hash.
    def self.modes
      @modes ||= parse_modes
    end

    # Returns the default mode label.
    def self.default_mode
      ENV.fetch('BROUTER_DEFAULT_MODE', modes.keys.first)
    end

    # Reset cached modes (useful for testing).
    def self.reset_modes!
      @modes = nil
    end

    private

    def fetch_route(from, to, profile, alternativeidx)
      response = HTTParty.get(
        @brouter_url,
        query: {
          lonlats: "#{from[:lon]},#{from[:lat]}|#{to[:lon]},#{to[:lat]}",
          profile: profile,
          alternativeidx: alternativeidx,
          format: 'geojson'
        },
        timeout: 30
      )

      unless response.success?
        raise RoutingError, 'No route found between these points. They may be in an area without routing data.'
      end

      geojson = JSON.parse(response.body)
      feature = geojson.dig('features', 0)
      raise RoutingError, 'No route found between these points.' unless feature

      coordinates = feature.dig('geometry', 'coordinates')
      raise RoutingError, 'No route found between these points.' if coordinates.blank?

      coordinates
    rescue HTTParty::Error, JSON::ParserError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise RoutingError, 'Could not connect to the routing service. Please try again later.'
    end

    def self.parse_modes
      env = ENV.fetch('BROUTER_MODES', nil)
      return DEFAULT_MODES if env.blank?

      env.split(',').each_with_object({}) do |pair, hash|
        label, profile = pair.strip.split(':', 2)
        hash[label.strip] = profile.strip if label.present? && profile.present?
      end
    end

    private_class_method :parse_modes
  end
end
