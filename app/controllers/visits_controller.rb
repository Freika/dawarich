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
             .order(started_at: order_by)
             .group_by { |visit| visit.started_at.to_date }
             .map { |k, v| { date: k, visits: v } }

    @suggested_visits_count = current_user.visits.suggested.count

    @visits = Kaminari.paginate_array(visits).page(params[:page]).per(10)
  end

  def update
    if @visit.update(visit_params)
      redirect_to visits_url, notice: 'Visit was successfully updated.', status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_visit
    @visit = current_user.visits.find(params[:id])
  end

  def visit_params
    params.require(:visit).permit(:name, :started_at, :ended_at, :status)
  end
end
