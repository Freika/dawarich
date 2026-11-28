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
      }.merge(route_data)
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

    def route_data
      recorded = days.select { |day| day[:has_data] }
      keyed = recorded.index_by { |day| day[:date].iso8601 }

      {
        'shared-trip-map-tiles-url-value': "/api/v1/shared/#{@link.id}/tiles/{z}/{x}/{y}.mvt",
        'shared-trip-map-day-keys-value': keyed.keys,
        'shared-trip-map-day-bounds-value': keyed.transform_values { |day| day[:bounds] },
        'shared-trip-map-day-endpoints-value': keyed.transform_values do |day|
          { first: day[:first_coordinates], last: day[:last_coordinates] }
        end,
        'shared-trip-map-full-bounds-value': full_bounds(recorded.map { |day| day[:bounds] })
      }
    end

    def full_bounds(day_bounds)
      return [] if day_bounds.empty?

      corners = day_bounds.flatten(1)
      [[corners.map(&:first).min, corners.map(&:last).min], [corners.map(&:first).max, corners.map(&:last).max]]
    end

    def gallery_row_data(day_key)
      data = row_data(day_key)
      data.merge(controller: 'lazy-gallery', action: [data[:action], 'toggle->lazy-gallery#toggle'].compact.join(' '))
    end
  end
end
