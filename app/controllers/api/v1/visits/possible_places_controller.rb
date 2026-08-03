# frozen_string_literal: true

class Api::V1::Visits::PossiblePlacesController < ApiController
  def index
    visit = current_api_user.visits.find(params[:id])
    lat, lon = visit.center
    suggestions = Places::NearbySearch.new(latitude: lat, longitude: lon, cache: true).call
    suggestions = prepend_current_place(visit, suggestions)
    render json: suggestions
  rescue ActiveRecord::RecordNotFound
    render json: { error: I18n.t('controllers.api.v1.visits.possible_places.visit_not_found') }, status: :not_found
  end

  private

  def prepend_current_place(visit, suggestions)
    return suggestions unless visit.place

    current = serialize_existing_place(visit.place)
    filtered = if current[:osm_id].present?
                 suggestions.reject { |s| s[:osm_id] == current[:osm_id] }
               else
                 suggestions
               end

    [current] + filtered
  end

  def serialize_existing_place(place)
    {
      id: place.id,
      name: place.name,
      latitude: place.lat,
      longitude: place.lon,
      osm_id: place.osm_id,
      osm_type: place.osm_type,
      osm_key: place.osm_key,
      osm_value: place.osm_value,
      city: place.city,
      country: place.country,
      source: place.source,
      geodata: place.geodata
    }
  end
end
