# frozen_string_literal: true

class VisitsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_visit, only: %i[update]

  def index
    order_by = params[:order_by] || 'asc'
    status   = params[:status]   || 'confirmed'

    visits = current_user
             .visits
             .where(status:)
             .includes(%i[suggested_places area points place])
             .order(started_at: order_by)

    @suggested_visits_count = current_user.visits.suggested.count
    @visits = visits.page(params[:page]).per(10)
  end

  def update
    update_visit_name_from_place if visit_params[:place_id].present?

    if @visit.update(visit_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "visit_name_#{@visit.id}",
            partial: 'visits/name', locals: { visit: @visit }
          )
        end
        format.html { redirect_back(fallback_location: visits_path(status: :suggested)) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "visit_name_#{@visit.id}",
            partial: 'visits/name', locals: { visit: @visit }
          )
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  private

  def set_visit
    @visit = current_user.visits.find(params[:id])
  end

  def update_visit_name_from_place
    place = current_user.places.find_by(id: visit_params[:place_id])
    @visit.name = place.name if place
  end

  def visit_params
    params.require(:visit).permit(:name, :place_id, :started_at, :ended_at, :status)
  end
end
