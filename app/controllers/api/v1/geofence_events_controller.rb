# frozen_string_literal: true

class Api::V1::GeofenceEventsController < ApiController
  before_action :authenticate_active_api_user!

  def index
    events = current_api_user.geofence_events.real.order(occurred_at: :desc)
    events = events.where(area_id: params[:area_id]) if params[:area_id].present?
    events = events.page(params[:page]).per(params[:per_page] || 50)
    render json: events.map { |e| GeofenceEventSerializer.new(e).call }
  end
end
