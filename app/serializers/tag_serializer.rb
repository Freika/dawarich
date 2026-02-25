# frozen_string_literal: true

class TagSerializer
  def initialize(tag)
    @tag = tag
  end

  def call
    {
      tag_id: tag.id,
      tag_name: tag.name,
      tag_icon: tag.icon,
      tag_color: tag.color,
      radius_meters: tag.privacy_radius_meters,
      places: places
    }
  end

  private

  attr_reader :tag

  def places
    tag.places.map do |place|
      {
        id: place.id,
        name: place.name,
        latitude: place.latitude.to_f,
        longitude: place.longitude.to_f
      }
    end
  end
end
