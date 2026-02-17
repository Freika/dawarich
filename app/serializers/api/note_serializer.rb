# frozen_string_literal: true

class Api::NoteSerializer
  def initialize(note)
    @note = note
  end

  def call
    {
      id: note.id,
      title: note.title,
      body: note.body&.to_plain_text,
      latitude: note.latitude&.to_f,
      longitude: note.longitude&.to_f,
      attachable_type: note.attachable_type,
      attachable_id: note.attachable_id,
      date: note.date,
      noted_at: note.noted_at,
      created_at: note.created_at,
      updated_at: note.updated_at
    }
  end

  private

  attr_reader :note
end
