# frozen_string_literal: true

class Api::V1::Tiles::TripsController < ApiController
  include TileCacheable

  TILE_SCHEMA_VERSION = 1
  MAX_EXCLUDE_WINDOWS = 50
  EXCLUDE_FORMAT = /\A\d+-\d+(,\d+-\d+)*\z/

  before_action :set_trip
  before_action :reject_invalid_exclude

  private

  def set_trip
    @trip = current_api_user.trips.find(params[:trip_id])
  end

  def reject_invalid_exclude
    return if exclude_windows

    force_uncacheable_response
    render json: { error: 'exclude must be a list of start-end epoch pairs' }, status: :bad_request
  end

  def exclude_windows
    return @exclude_windows if defined?(@exclude_windows)

    @exclude_windows = parse_exclude_windows(params[:exclude].to_s)
  end

  def parse_exclude_windows(raw)
    return [] if raw.blank?
    return unless raw.match?(EXCLUDE_FORMAT)

    windows = raw.split(',').map { |pair| pair.split('-').map(&:to_i) }
    return if windows.size > MAX_EXCLUDE_WINDOWS || windows.any? { |from, to| from >= to }

    windows.sort.uniq
  end

  def tile_query
    Trips::RoutesTileQuery.new(
      trip: @trip, z: params[:z], x: params[:x], y: params[:y], timezone: current_api_user.timezone_iana,
      points_scope: @trip.plan_scoped_route_points, exclude_windows:
    )
  end

  def tile_schema_version
    [TILE_SCHEMA_VERSION, current_api_user.timezone_iana, exclude_windows]
  end

  def tile_epoch_component
    [@trip.recording_devices_cache_key, @trip.updated_at.to_i]
  end

  def range_requested?
    false
  end

  def cacheable_start_at
    @trip.started_at.to_i
  end

  def cacheable_end_at
    @trip.ended_at.to_i
  end
end
