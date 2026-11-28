# frozen_string_literal: true

class Users::ImportData::Notes
  include Users::ImportData::PlaceLookup

  ATTRIBUTES = %w[title body noted_at source_digest latitude longitude].freeze

  def initialize(user, notes_data)
    @user = user
    @notes_data = notes_data
  end

  def call
    return 0 unless notes_data.is_a?(Array)

    created = notes_data.count { |note_data| note_data.is_a?(Hash) && import_note(note_data) }
    Rails.logger.info "Notes import completed. Created: #{created}"
    created
  end

  private

  attr_reader :user, :notes_data

  def import_note(note_data)
    attributes = note_data.slice(*ATTRIBUTES)
    attachable = find_attachable(note_data)
    return false if user.notes.exists?(noted_at: attributes['noted_at'], body: attributes['body'])
    return false if attachable && overwrite_same_day_note(attachable, attributes)

    # A note whose attachable is gone, or no longer fits it, is still the
    # user's writing: keep it as a standalone note rather than drop it.
    user.notes.build(attributes.merge(attachable: attachable)).save || user.notes.build(attributes).save
  end

  # An attachable holds one note per day, and restoring a planned trip already
  # recreates its synced day notes. The exported text is what the user last saw.
  def overwrite_same_day_note(attachable, attributes)
    date = Time.zone.parse(attributes['noted_at'].to_s)&.utc&.to_date
    existing = date && attachable.notes.for_date(date).first
    return false unless existing

    existing.update(attributes.slice('title', 'body', 'source_digest'))
    true
  end

  def find_attachable(note_data)
    reference = note_data['attachable_reference']
    return nil unless reference.is_a?(Hash)

    case note_data['attachable_type']
    when 'Trip' then user.trips.find_by(reference.slice('name', 'started_at', 'ended_at'))
    when 'Visit' then user.visits.find_by(reference.slice('name', 'started_at', 'ended_at'))
    # Legacy areas are imported as places.
    when 'Place', 'Area' then find_place_by_reference(*reference.values_at('name', 'latitude', 'longitude'))
    end
  end
end
