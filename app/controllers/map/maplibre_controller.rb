# frozen_string_literal: true

module Map
  class MaplibreController < ApplicationController
    include SafeTimestampParser
    include ImportTimeWindow
    include VideoStudioContext

    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = parsed_start_at
      @end_at = parsed_end_at
      @import_id = import_record&.id
      @current_position = current_position
      @latest_data_date = latest_data_date
      @data_outside_view = @latest_data_date.nil? && current_user.points.exists?
      @exploration_bounds = exploration_bounds
      @exploration_snapshot_id = exploration_snapshot_id if @exploration_bounds

      # Tag chips displayed in the rail; capped so the list doesn't explode.
      @timeline_tags = current_user.tags.order(:name).limit(8)

      # Theme tokens power both the poster studio and the Appearance section's
      # custom map colors.
      load_video_studio_context
    end

    private

    def exploration_snapshot_id
      snapshot_id = Integer(params[:exploration_snapshot], exception: false)
      return unless snapshot_id

      cards = current_user.achievement_collectibles.where(series: 'city', subject_key: params[:exploration_city],
                                                          revoked_at: nil)
      snapshot_id if cards.where("data->>'snapshot_id' = ?", snapshot_id.to_s).exists?
    end

    def exploration_bounds
      code = params[:exploration_city].to_s
      return if code.blank? || !current_user.achievement_city_selections.exists?(territory_code: code)

      city = Exploration::Territory.find_by(dataset_id: Exploration::Geography.current&.id, kind: 'city', code: code)
      return unless city

      west, south, east, north = Exploration::Territory.where(id: city.id).pick(
        Arel.sql('ST_XMin(Box3D(boundary))'), Arel.sql('ST_YMin(Box3D(boundary))'),
        Arel.sql('ST_XMax(Box3D(boundary))'), Arel.sql('ST_YMax(Box3D(boundary))')
      )
      [[west, south], [east, north]]
    end

    def latest_points
      current_user.scoped_points.without_raw_data.complete.not_anomaly.order(timestamp: :desc)
    end

    def latest_point
      return @latest_point if defined?(@latest_point)

      @latest_point = latest_points.first
    end

    # The day the empty-period state offers to jump to, in the same zone
    # `?date=` is read in. It is the latest day the map can actually show:
    # a day spent inside a Privacy Zone would open as another empty period.
    def latest_data_date
      masker = current_privacy_zone_masker
      point = masker.any? ? masker.mask_points(latest_points).first : latest_point
      return unless point

      zone = current_user.safe_settings.timezone.presence || 'UTC'
      Time.zone.at(point.timestamp).in_time_zone(zone).to_date
    end

    def current_position
      point = latest_point
      return if point.nil? || current_privacy_zone_masker.in_zone?(point.lon, point.lat)

      { longitude: point.lon, latitude: point.lat, timestamp: point.timestamp }
    end

    def start_at
      return safe_timestamp(params[:start_at]) if params[:start_at].present?
      return diary_month.begin.to_i if diary_month
      return date_param_range.begin.to_i if date_param_range
      return import_window_start if import_window_start

      Time.zone.today.beginning_of_day.to_i
    end

    def end_at
      return safe_timestamp(params[:end_at]) if params[:end_at].present?
      return diary_month.end.to_i if diary_month
      return date_param_range.end.to_i if date_param_range
      return import_window_end if import_window_end

      Time.zone.today.end_of_day.to_i
    end

    # When the URL carries only `?date=` (deep-links, the unified-timeline
    # redirect, the Timeline panel's own day navigation) — but no explicit
    # start_at/end_at — derive the map's data window from that day so the
    # map, the top date-range form, and the Timeline panel all agree.
    # Without this the map silently stays on "today" while the panel shows
    # the requested day (the C1 desync).
    def date_param_range
      return @date_param_range if defined?(@date_param_range)

      @date_param_range =
        if params[:date].present?
          tz = current_user.timezone_or_utc
          Time.use_zone(tz) do
            date = params[:date] == 'today' ? Date.current : safe_parse_date(params[:date])
            date&.all_day
          end
        end
    end

    # `?month=2026-11` opens that month, `?month=latest` the month of the
    # latest note (the Diary menu item). A `date=` beside it only picks the
    # day to select inside the month.
    def diary_month
      return @diary_month if defined?(@diary_month)

      @diary_month =
        if params[:month].present? && params[:start_at].blank?
          tz = current_user.safe_settings.timezone.presence || 'UTC'
          Time.use_zone(tz) do
            day = safe_parse_date("#{params[:month]}-01") if params[:month].match?(/\A\d{4}-\d{2}\z/)
            day ||= current_user.notes.standalone.maximum(:noted_at)&.in_time_zone&.to_date
            (day || Date.current).in_time_zone.all_month
          end
        end
    end

    def safe_parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parsed_start_at
      Time.zone.at(start_at)
    end

    def parsed_end_at
      Time.zone.at(end_at)
    end
  end
end
