# frozen_string_literal: true

module Map
  class MaplibreController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = parsed_start_at
      @end_at = parsed_end_at

      # Status counts shown in the Timeline tab's FILTER section — scoped to
      # the calendar's currently-visible month so the numbers reflect "what
      # you're looking at" rather than the user's lifetime totals.
      summary = Timeline::MonthSummary.new(user: current_user, month: timeline_month).call
      @status_counts = summary[:status_counts] || {}

      # Pending-suggestion badge on the map-edge cluster — kept lifetime-scoped
      # so the user sees their global review backlog at a glance, regardless
      # of which month the calendar lands on.
      @suggestions_pending_count = current_user.scoped_visits.suggested.count

      # Tag chips displayed in the rail; capped so the list doesn't explode.
      @timeline_tags = current_user.tags.order(:name).limit(8)
    end

    private

    # Reuses the same month-resolution rule as the calendar helper so the
    # filter pills are aligned with whatever month the calendar lands on
    # (params[:date] > params[:start_at] > today in user's tz).
    def timeline_month
      tz = current_user.safe_settings.timezone.presence || 'UTC'
      candidate = params[:date].presence || params[:start_at].presence
      if candidate
        parsed = begin
          Date.parse(candidate)
        rescue StandardError
          nil
        end
      end
      parsed || Time.use_zone(tz) { Date.current }
    end

    def start_at
      if params[:import_id].present?
        import = current_user.imports.find(params[:import_id])
        return import.points.minimum(:timestamp) || Time.zone.today.beginning_of_day.to_i
      end

      return safe_timestamp(params[:start_at]) if params[:start_at].present?

      Time.zone.today.beginning_of_day.to_i
    end

    def end_at
      if params[:import_id].present?
        import = current_user.imports.find(params[:import_id])
        return import.points.maximum(:timestamp) || Time.zone.today.end_of_day.to_i
      end

      return safe_timestamp(params[:end_at]) if params[:end_at].present?

      Time.zone.today.end_of_day.to_i
    end

    def parsed_start_at
      Time.zone.at(start_at)
    end

    def parsed_end_at
      Time.zone.at(end_at)
    end
  end
end
