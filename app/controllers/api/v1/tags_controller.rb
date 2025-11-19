# frozen_string_literal: true

module Api
  module V1
    class TagsController < ApiController
      def privacy_zones
        zones = current_api_user.tags.privacy_zones.includes(:places)

        render json: zones.map { |tag| TagSerializer.new(tag).call }
      end
    end
  end
end
