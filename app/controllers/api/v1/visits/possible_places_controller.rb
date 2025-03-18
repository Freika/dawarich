# frozen_string_literal: true

class Api::V1::Visits::PossiblePlacesController < ApiController
  def index
    visit = current_api_user.visits.find(params[:id])
    possible_places = visit.suggested_places.map do |place|
      Api::PlaceSerializer.new(place).call
    end

    render json: possible_places
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Visit not found' }, status: :not_found
  end
end
