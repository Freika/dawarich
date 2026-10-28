# frozen_string_literal: true

class Api::V1::Maps::StatisticsController < ApiController
  def index
    start_at = parse_timestamp(params[:start_at])
    end_at = parse_timestamp(params[:end_at])
    response.headers['Cache-Control'] = 'no-store'
    unless start_at && end_at && start_at <= end_at
      return render json: { error: 'Provide a valid start_at and end_at range' }, status: :bad_request
    end

    render json: Maps::RangeStatistics.new(current_api_user, start_at:, end_at:, import_id: params[:import_id]).call
  rescue ActiveRecord::QueryCanceled
    render json: { error: 'Statistics query timed out; shorten the date range' }, status: :service_unavailable
  end

  private

  def parse_timestamp(value)
    return if value.blank?

    timestamp = value.match?(/\A\d+\z/) ? value.to_i : Time.zone.parse(value)&.to_i
    timestamp if timestamp&.between?(0, Time.utc(2100).to_i)
  rescue ArgumentError, TypeError
    nil
  end
end
