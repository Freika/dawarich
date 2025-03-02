# frozen_string_literal: true

class Api::V1::VisitsController < ApiController
  def index
    start_time = begin
      Time.zone.parse(params[:start_at])
    rescue StandardError
      Time.zone.now.beginning_of_day
    end
    end_time = begin
      Time.zone.parse(params[:end_at])
    rescue StandardError
      Time.zone.now.end_of_day
    end

    visits =
      Visit
      .includes(:place)
      .where(user: current_api_user)
      .where('started_at >= ? AND ended_at <= ?', start_time, end_time)
      .order(started_at: :desc)

    serialized_visits = visits.map do |visit|
      Api::VisitSerializer.new(visit).call
    end

    render json: serialized_visits
  end

  def update
    visit = current_api_user.visits.find(params[:id])
    visit = update_visit(visit)

    render json: visit
  end

  private

  def visit_params
    params.require(:visit).permit(:name, :place_id, :status)
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
