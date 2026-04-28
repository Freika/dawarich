# frozen_string_literal: true

module Map
  class TimelineFeedsController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!
    layout false

    def index
      @days = Timeline::DayAssembler.new(
        current_user,
        start_at: parsed_start_at.iso8601,
        end_at: parsed_end_at.iso8601,
        distance_unit: current_user.safe_settings.distance_unit
      ).call
      @distance_unit = current_user.safe_settings.distance_unit
    end

    def track_info
      @track = current_user.tracks.find(params[:id])
      @distance_unit = current_user.safe_settings.distance_unit
    end

    def calendar
      month = params[:month].presence || Date.current.strftime('%Y-%m')
      @summary = Timeline::MonthSummary.new(user: current_user, month: month).call
      counts = @summary[:status_counts] || {}

      respond_to do |format|
        # Calendar prev/next links request turbo_stream so we can update both
        # the calendar grid AND the FILTER pills (which are scoped to the
        # visible month) in one round-trip.
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('timeline-calendar-frame',
                                 partial: 'calendar',
                                 locals: { summary: @summary }),
            turbo_stream.replace('filter-count-confirmed',
                                 partial: 'filter_count',
                                 locals: { status: 'confirmed', count: counts['confirmed'].to_i }),
            turbo_stream.replace('filter-count-suggested',
                                 partial: 'filter_count',
                                 locals: { status: 'suggested', count: counts['suggested'].to_i }),
            turbo_stream.replace('filter-count-declined',
                                 partial: 'filter_count',
                                 locals: { status: 'declined', count: counts['declined'].to_i })
          ]
        end
        # Initial frame load on page open is an HTML request — fall back to
        # the bare calendar partial.
        format.html do
          render partial: 'calendar', locals: { summary: @summary }
        end
      end
    end

    private

    def parsed_start_at
      Time.zone.at(safe_timestamp(params[:start_at]))
    end

    def parsed_end_at
      Time.zone.at(safe_timestamp(params[:end_at]))
    end
  end
end
