# frozen_string_literal: true

require "net/http"
require "json"

class Api::V1::RouteEditorController < ApiController
  def preview
    locations = preview_params[:locations]

    if locations.blank? || locations.size < 2
      render json: { error: "At least 2 locations are required" }, status: :unprocessable_entity
      return
    end

    payload = {
      locations: locations.map do |location|
        {
          lat: location[:lat].to_f,
          lon: location[:lon].to_f,
          type: location[:type].presence || "break"
        }
      end,
      costing: "auto",
      format: "osrm",
      shape_format: "geojson"
    }

    response_json = call_valhalla("/route", payload)

    coordinates = response_json.dig("routes", 0, "geometry", "coordinates")
    if coordinates.blank?
      render json: { error: "No route geometry returned from Valhalla" }, status: :unprocessable_entity
      return
    end

    render json: {
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          properties: {
            source: "route-editor-preview"
          },
          geometry: {
            type: "LineString",
            coordinates: coordinates
          }
        }
      ]
    }
  rescue StandardError => e
    Rails.logger.error("[RouteEditorController] preview failed: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def preview_params
    params.permit(:api_key, locations: %i[lat lon type])
  end

  def call_valhalla(path, payload)
    base_url = ENV.fetch("VALHALLA_URL", "http://host.docker.internal:8002")
    uri = URI.join(base_url, path)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Valhalla request failed: #{response.code} #{response.body}"
    end

    JSON.parse(response.body)
  end
end