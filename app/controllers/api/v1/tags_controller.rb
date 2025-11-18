# frozen_string_literal: true

module Api
  module V1
    class TagsController < ApiController
      def privacy_zones
        zones = current_api_user.tags.privacy_zones.includes(:places)

        render json: zones.map { |tag|
          {
            tag_id: tag.id,
            tag_name: tag.name,
            tag_icon: tag.icon,
            tag_color: tag.color,
            radius_meters: tag.privacy_radius_meters,
            places: tag.places.map { |place|
              {
                id: place.id,
                name: place.name,
                latitude: place.latitude,
                longitude: place.longitude
              }
            }
          }
        }
      end
    end
  end
end
