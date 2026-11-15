# frozen_string_literal: true

class Api::V1::GeofenceEventsController < ApiController
  include SafeTimestampParser

  before_action :authenticate_active_api_user!

  def index
    from = parse_time_param(params[:start_at])
    to = parse_time_param(params[:end_at])
    events = current_api_user.scoped_geofence_events.includes(:place).order(occurred_at: :desc, id: :desc)
                             .for_place(params[:place_id])
                             .occurred_within_days(from, to)
                             .page(params[:page]).per(per_page)

    set_pagination_headers(events)
    render json: events.map { |event| GeofenceEventSerializer.new(event).call }
  end

  private

  def per_page
    params[:per_page].to_i.clamp(1, 200).then { |value| params[:per_page].present? ? value : 50 }
  end
end
