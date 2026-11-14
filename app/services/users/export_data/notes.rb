# frozen_string_literal: true

class Users::ExportData::Notes
  ATTRIBUTES = %w[title body noted_at source_digest created_at updated_at].freeze

  def initialize(user)
    @user = user
  end

  def call
    user.notes.includes(:attachable).find_each.map { |note| build_note_hash(note) }
  end

  private

  attr_reader :user

  def build_note_hash(note)
    note.as_json(only: ATTRIBUTES).merge(
      'latitude' => note.latitude,
      'longitude' => note.longitude,
      'attachable_type' => note.attachable_type,
      'attachable_reference' => attachable_reference(note.attachable)
    )
  end

  # Ids do not survive a move to another account, so an attachable is
  # described by the same natural key its own importer matches on.
  def attachable_reference(attachable)
    case attachable
    when Trip, Visit
      attachable.as_json(only: %w[name started_at ended_at])
    when Place
      { 'name' => attachable.name, 'latitude' => attachable.lat, 'longitude' => attachable.lon }
    when Area
      { 'name' => attachable.name, 'latitude' => attachable.latitude.to_f, 'longitude' => attachable.longitude.to_f }
    end
  end
end
