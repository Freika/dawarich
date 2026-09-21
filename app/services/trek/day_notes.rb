# frozen_string_literal: true

module Trek
  # Puts TREK day notes into the trip's native day notes. A day's note is only
  # touched when its TREK text changed since the previous snapshot, so a note
  # the user deleted stays deleted; and only while it still holds exactly what
  # a synchronization wrote, so the user's own words always win.
  class DayNotes
    def self.text_for(day)
      lines = [day['notes'].to_s.strip]
      Array(day['day_notes']).each do |note|
        lines << [note['time'].presence, note['text'].to_s.strip].compact.join(' ')
      end
      lines.compact_blank.join("\n").first(Note::MAX_BODY_LENGTH).presence
    end

    def initialize(trip, previous_snapshot)
      @trip = trip
      @previous_snapshot = previous_snapshot
    end

    def call
      before = texts_by_date(@previous_snapshot)
      after = texts_by_date(@trip.source_snapshot)
      (before.keys | after.keys).each do |date|
        next if before[date] == after[date]

        synchronize_day(date, after[date])
      end
    end

    private

    def synchronize_day(date, text)
      note = @trip.notes.for_date(date).first
      if text.nil?
        note.destroy! if note&.synced_from_source?
      elsif note.nil?
        @trip.notes.create!(user: @trip.user, date:, body: text, source_digest: Note.body_digest(text))
      elsif note.synced_from_source?
        note.update!(body: text, source_digest: Note.body_digest(text))
      end
    end

    def texts_by_date(snapshot)
      Array(snapshot&.dig('days')).each_with_object({}) do |day, texts|
        text = self.class.text_for(day)
        texts[Date.parse(day['date'].to_s)] = text if text
      end
    end
  end
end
