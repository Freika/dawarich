# frozen_string_literal: true

class DataMigrations::BackfillPlaceNameLocksJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 1_000

  def perform
    locked_total = 0

    candidates.in_batches(of: BATCH_SIZE) do |batch|
      ids = batch.reject { |place| machine_named?(place) }.map(&:id)
      next if ids.empty?

      locked_total += Place.where(id: ids, name_locked_at: nil).update_all(name_locked_at: Time.current)
    end

    Rails.logger.info("[#{self.class}] locked #{locked_total} user-named places")
  end

  private

  def candidates
    Place.where(name_locked_at: nil).where.not(name: Place::DEFAULT_NAME)
  end

  def machine_named?(place)
    properties = place.geodata.is_a?(Hash) ? place.geodata['properties'] : nil
    return false if properties.blank?

    [
      Visits::Names::Builder.build_from_properties(properties),
      geocoder_style_name(properties)
    ].compact.include?(place.name)
  end

  # Mirrors ReverseGeocoding::Places::FetchData#place_name, the format machine
  # names were written in before name locking existed.
  def geocoder_style_name(properties)
    name = properties['name']
    type = properties['osm_value']&.capitalize&.gsub('_', ' ')
    address = "#{properties['postcode']} #{properties['street']}"
    address += " #{properties['housenumber']}" if properties['housenumber'].present?
    name ||= address

    "#{name} (#{type})"
  end
end
