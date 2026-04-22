# frozen_string_literal: true

class GeofenceEventsController < ApplicationController
  before_action :authenticate_user!

  def index
    @events = current_user.geofence_events.order(occurred_at: :desc)
    @events = @events.where(area_id: params[:area_id]) if params[:area_id].present?
    @events = @events.page(params[:page]).per(50)
    @areas = current_user.areas.order(:name)
  end
end
