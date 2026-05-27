# frozen_string_literal: true

class Places::GeojsonPointImporter
  include Places::BulkInsertable

  DEFAULT_NAME = 'Imported place'

  attr_reader :import, :user_id, :features

  def initialize(import, user_id, features)
    @import = import
    @user_id = user_id
    @features = features
  end

  def call
    return 0 if features.blank?

    features.each_slice(BATCH_SIZE).sum do |slice|
      insert_places(slice.filter_map { |feature| prepare_place(feature) })
    end
  end

  private

  def prepare_place(feature)
    feature = feature.with_indifferent_access
    coordinates = feature.dig(:geometry, :coordinates)
    return if coordinates.blank?

    place_row(
      name: feature.dig(:properties, :name),
      latitude: coordinates[1],
      longitude: coordinates[0],
      source: Place.sources[:geojson_point]
    )
  end

  def default_place_name
    DEFAULT_NAME
  end
end
