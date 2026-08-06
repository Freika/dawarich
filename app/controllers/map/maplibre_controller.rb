# frozen_string_literal: true

module Map
  class MaplibreController < ApplicationController
    include SafeTimestampParser
    include ImportTimeWindow
    include PosterStudioContext

    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = parsed_start_at
      @end_at = parsed_end_at
      @import_id = import_record&.id

      # Tag chips displayed in the rail; capped so the list doesn't explode.
      @timeline_tags = current_user.tags.order(:name).limit(8)

      # Theme tokens power both the poster studio and the Appearance section's
      # custom map colors.
      load_poster_studio_context
    end

    private

    def start_at
      return safe_timestamp(params[:start_at]) if params[:start_at].present?
      return date_param_range.begin.to_i if date_param_range
      return import_window_start if import_window_start

      Time.zone.today.beginning_of_day.to_i
    end

    def end_at
      return safe_timestamp(params[:end_at]) if params[:end_at].present?
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
          tz = current_user.safe_settings.timezone.presence || 'UTC'
          Time.use_zone(tz) do
            date = params[:date] == 'today' ? Date.current : safe_parse_date(params[:date])
            date&.all_day
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
