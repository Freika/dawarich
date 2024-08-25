# frozen_string_literal: true

class Api::V1::VisitsController < ApiController
  def update
    visit = current_api_user.visits.find(params[:id])
    visit = update_visit(visit)

    render json: visit
  end

  private

  def visit_params
    params.require(:visit).permit(:name, :place_id)
  end

  def update_visit(visit)
    visit_params.each do |key, value|
      visit[key] = value
      visit.name = visit.place.name if visit_params[:place_id].present?
    end

    visit.save!

    visit
  end
end
