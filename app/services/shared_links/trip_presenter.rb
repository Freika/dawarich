# frozen_string_literal: true

module SharedLinks
  class TripPresenter
    ROW_ACTIONS = 'mouseenter->shared-trip-map#hoverDay ' \
                  'mouseleave->shared-trip-map#leaveDay ' \
                  'click->shared-trip-map#toggleDay'

    def initialize(link, trip)
      @link = link
      @trip = trip
      @ctx = SharedLinkContext.new(link)
    end

    attr_reader :link, :trip

    def unit
      @link.user.safe_settings.distance_unit
    end

    def timezone
      @link.user.timezone_iana
    end

    def show_map?
      @ctx.show_route?
    end

    delegate :show_stats?, to: :@ctx

    delegate :show_days?, to: :@ctx

    delegate :show_day_notes?, to: :@ctx

    def description?
      @ctx.show_description? && @trip.description.body.present?
    end

    def wrapper_data
      return {} unless show_map?

      {
        controller: 'shared-trip-map',
        'shared-trip-map-link-id-value': @link.id,
        'shared-trip-map-show-photos-value': @ctx.show_photos?,
        'shared-trip-map-by-day-value': true,
        'shared-trip-map-timezone-value': timezone
      }
    end

    def days
      @days ||= SharedLinks::TripDays.new(@trip, timezone: timezone, unit: unit).call
    end

    def days?
      show_days? && days.any?
    end

    def notes
      @notes ||= show_day_notes? ? @trip.notes.index_by(&:date) : {}
    end

    def note_for(day)
      notes[day[:date]]
    end

    def photos_by_day
      return {} unless @ctx.show_photos?

      @photos_by_day ||= SharedLinks::TripPhotos.new(@link, timezone: timezone).call
    end

    def photos_for(day)
      photos_by_day[day[:date]] || []
    end

    def interactive_class
      show_map? ? ' cursor-pointer transition-colors hover:bg-base-300' : ''
    end

    def row_data(day_key)
      return {} unless show_map?

      { day_key: day_key, action: ROW_ACTIONS, 'shared-trip-map-day-key-param': day_key }
    end
  end
end
