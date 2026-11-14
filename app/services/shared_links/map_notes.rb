# frozen_string_literal: true

module SharedLinks
  # The owner's map notes a shared link shows: those about a moment inside the
  # link's period, and only when the owner switched them on. Read at view time,
  # so a note written later about the shared period appears too. Notes inside a
  # privacy zone stay out, as everything else a zone hides.
  class MapNotes
    def initialize(link)
      @link = link
    end

    def call
      period = shown_period
      return Note.none unless period

      notes = @link.user.notes.standalone.where(noted_at: period).order(:noted_at)
      Maps::PrivacyZoneMasker.new(@link.user).mask_notes(notes)
    end

    private

    def shown_period
      return unless SharedLinkContext.new(@link).show_map_notes?

      @link.track? ? track_period : timeline_period
    end

    def track_period
      track = @link.resource
      track && (track.start_at..track.end_at)
    end

    def timeline_period
      zone = Time.find_zone(@link.user.timezone_iana) || Time.find_zone('UTC')
      first_day = zone.parse(@link.settings['start_date'].to_s)
      last_day = zone.parse(@link.settings['end_date'].to_s)
      first_day && last_day && (first_day.beginning_of_day..last_day.end_of_day)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
