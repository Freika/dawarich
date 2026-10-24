# frozen_string_literal: true

class Api::V1::GeofenceEventsController < ApiController
  before_action :authenticate_active_api_user!

  def index
    events = current_api_user.geofence_events.real.includes(:area).order(occurred_at: :desc, id: :desc)
    events = events.where(area_id: params[:area_id]) if params[:area_id].present?
    events = within_dates(events).page(params[:page]).per(per_page)

    response.set_header('X-Current-Page', events.current_page.to_s)
    response.set_header('X-Total-Pages', events.total_pages.to_s)
    render json: events.map { |event| GeofenceEventSerializer.new(event).call }
  end

  private

  def within_dates(events)
    start_at = parse_date(params[:start_at])&.beginning_of_day
    end_at = parse_date(params[:end_at])&.end_of_day
    events = events.where(occurred_at: start_at..) if start_at
    events = events.where(occurred_at: ..end_at) if end_at
    events
  end

  def parse_date(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  def per_page
    params[:per_page].to_i.clamp(1, 200).then { |value| params[:per_page].present? ? value : 50 }
  end
end
