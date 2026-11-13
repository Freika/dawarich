# frozen_string_literal: true

module Timeline
  # The written layer of a day: the user's map notes, and a generated line
  # naming where the day went. Notes are listed beside the entries rather than
  # among them, so readers of `entries` keep seeing only visits and journeys.
  module NoteEntries
    FACTS_MAX_PLACES = 6

    private

    # Not plan-scoped on purpose: notes are the user's own writing (ADR-0029).
    def fetch_notes
      user.notes.standalone.in_date_range(start_at, end_at).order(:noted_at)
    end

    # A note inside a privacy zone is still the user's to read; only its
    # position is withheld, as for everything else the zone hides.
    def build_note_entry(note)
      hidden = @privacy_zone_masker&.in_zone?(note.longitude, note.latitude)

      {
        note_id: note.id,
        body: note.body,
        noted_at: note.noted_at.iso8601,
        latitude: hidden ? nil : note.latitude,
        longitude: hidden ? nil : note.longitude
      }
    end

    # "Home → Office → Home · 8.5 km". Built from names and numbers only, so it
    # needs no grammar and reads the same in every locale.
    def facts_line(visits, total_distance)
      names = visits.reject(&:declined?).sort_by(&:started_at).filter_map { |visit| short_place_name(visit) }
      names = names.chunk_while { |a, b| a == b }.map(&:first)
      return if names.empty?

      route = names.first(FACTS_MAX_PLACES).join(' → ')
      route += ' → …' if names.size > FACTS_MAX_PLACES
      total_distance.to_f.positive? ? "#{route} · #{total_distance} #{distance_unit}" : route
    end

    # A geocoded address is not a name anyone would say; skip visits without one.
    def short_place_name(visit)
      (visit.name.presence || visit.place&.name || visit.area&.name)&.split(',')&.first&.strip.presence
    end
  end
end
