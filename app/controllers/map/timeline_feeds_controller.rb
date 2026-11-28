# frozen_string_literal: true

module Map
  class TimelineFeedsController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!
    layout false

    NOTE_RESULTS = 50

    def index
      return render_note_results if params[:q].present?

      # A period longer than the assembler takes is read from its end: the
      # feed shows the latest days and says so, instead of showing nothing.
      limit = Timeline::DayAssembler::MAX_DAYS
      @clamped = (parsed_end_at.to_date - parsed_start_at.to_date).to_i >= limit
      feed_start = @clamped ? (parsed_end_at - (limit - 1).days).beginning_of_day : parsed_start_at

      @days = Timeline::DayAssembler.new(
        current_user,
        start_at: feed_start.iso8601,
        end_at: parsed_end_at.iso8601,
        distance_unit: current_user.safe_settings.distance_unit,
        privacy_zone_masker: current_privacy_zone_masker
      ).call
      @distance_unit = current_user.safe_settings.distance_unit
      # The day the frame was asked to render. Lets the empty state still show
      # the "< Weekday, Month D >" day navigator so users can step days even
      # when a day has no visits.
      @requested_date = parsed_start_at.to_date.iso8601
      # More than a day in one frame: each day collapses and one can be selected.
      # A whole day is 25 hours long when the clocks go back, and still one day;
      # a timed period that long has its ends on two dates.
      length = parsed_end_at - parsed_start_at
      @range = length > 25.hours || (length > 24.hours && parsed_start_at.to_date != parsed_end_at.to_date)
      @on_this_day = on_this_day_notes
    end

    def track_info
      @track = current_user.tracks.find(params[:id])
      @distance_unit = current_user.safe_settings.distance_unit
    end

    # What the period picker's calendar shows about each day of a month's
    # grid: how much was tracked (heat 1..5), whether a note was written, and
    # whether the plan's data window hides the day.
    def calendar
      month = params[:month].to_s.match?(/\A\d{4}-(0[1-9]|1[0-2])\z/) ? params[:month] : Date.current.strftime('%Y-%m')
      cells = Timeline::MonthSummary.new(user: current_user, month: month).call[:weeks].flatten
      noted = note_days(cells)

      render json: {
        days: cells.to_h do |cell|
          [cell[:date], { heat: cell[:heat_bucket].to_i, noted: noted.include?(cell[:date]),
                          disabled: cell[:disabled] ? true : false }]
        end
      }
    end

    private

    # The days of the calendar grid the user wrote a note about.
    def note_days(cells)
      dates = cells.map { |cell| Date.parse(cell[:date]) }
      current_user.notes.standalone
                  .where(noted_at: (dates.min - 1.day).beginning_of_day..(dates.max + 1.day).end_of_day)
                  .to_set { |note| note.date.iso8601 }
    end

    # A search looks through every note the user wrote, whatever
    # period is on screen. Not plan-scoped (ADR-0029).
    def render_note_results
      @notes = current_user.notes.standalone.matching(params[:q]).ordered.limit(NOTE_RESULTS)
      render :note_results
    end

    # Rereading is what a diary is for: under today, the notes written about
    # this date in earlier years. Not plan-scoped (ADR-0029).
    def on_this_day_notes
      # "Today is open" is judged by the instant, not the date: the browser
      # sends day bounds in its own time zone, which may not be the user's.
      return Note.none unless (parsed_start_at..parsed_end_at).cover?(Time.current)

      current_user.notes.standalone.on_this_day_before(Time.zone.today, Time.zone.tzinfo.name).ordered
    end

    def parsed_start_at
      Time.zone.at(safe_timestamp(params[:start_at]))
    end

    def parsed_end_at
      Time.zone.at(safe_timestamp(params[:end_at]))
    end
  end
end
