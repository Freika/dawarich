# frozen_string_literal: true

class Api::V1::Countries::VisitedController < ApiController
  def index
    start_at = parse_timestamp!(params[:start_at])
    end_at = parse_timestamp!(params[:end_at])
    raise ArgumentError, 'start_at must not be after end_at' if start_at > end_at

    return unless stale?(etag: etag_for(start_at, end_at), public: false)

    countries = Countries::VisitedQuery.new(
      user: current_api_user, start_at: start_at, end_at: end_at, import_id: params[:import_id]
    ).call
    render json: { countries: countries }
  rescue ArgumentError, TypeError
    render json: { error: 'start_at and end_at must be valid timestamps' }, status: :unprocessable_entity
  end

  private

  def parse_timestamp!(value)
    raise ArgumentError if value.blank?
    return Integer(value) if value.to_s.match?(/\A\d+\z/)

    Time.zone.iso8601(value.to_s).to_i
  end

  def etag_for(start_at, end_at)
    plan_window = if current_api_user.plan_restricted?
                    [current_api_user.effective_plan, current_api_user.data_window_start.to_date]
                  else
                    current_api_user.effective_plan
                  end
    [current_api_user.id, start_at, end_at, params[:import_id], plan_window,
     Points::TileEpoch.etag_component(current_api_user.id, start_at, end_at)]
  end
end
