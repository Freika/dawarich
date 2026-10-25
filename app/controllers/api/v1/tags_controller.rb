# frozen_string_literal: true

module Api
  module V1
    class TagsController < ApiController
      def privacy_zones
        zones = current_api_user.tags.privacy_zones.includes(:places)
        fingerprint = privacy_zone_masker.fingerprint
        response.set_header('X-Privacy-Zones-Fingerprint', fingerprint) if fingerprint

        render json: zones.map { |tag| TagSerializer.new(tag).call }
      end
    end
  end
end
