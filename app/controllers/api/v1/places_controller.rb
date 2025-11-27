# frozen_string_literal: true

module Api
  module V1
    class PlacesController < ApiController
      before_action :set_place, only: [:show, :update, :destroy]

      def index
        @places = current_api_user.places.includes(:tags, :visits)

        if params[:tag_ids].present?
          tag_ids = Array(params[:tag_ids])

          # Separate numeric tag IDs from "untagged"
          numeric_tag_ids = tag_ids.reject { |id| id == 'untagged' }.map(&:to_i)
          include_untagged = tag_ids.include?('untagged')

          if numeric_tag_ids.any? && include_untagged
            # Both tagged and untagged: return union (OR logic)
            tagged = current_api_user.places.includes(:tags, :visits).with_tags(numeric_tag_ids)
            untagged = current_api_user.places.includes(:tags, :visits).without_tags
            @places = Place.from("(#{tagged.to_sql} UNION #{untagged.to_sql}) AS places")
                           .includes(:tags, :visits)
          elsif numeric_tag_ids.any?
            # Only tagged places with ANY of the selected tags (OR logic)
            @places = @places.with_tags(numeric_tag_ids)
          elsif include_untagged
            # Only untagged places
            @places = @places.without_tags
          end
        end

        render json: @places.map { |place| serialize_place(place) }
      end

      def show
        render json: serialize_place(@place)
      end

      def create
        @place = current_api_user.places.build(place_params.except(:tag_ids))

        if @place.save
          add_tags if tag_ids.present?
          @place = current_api_user.places.includes(:tags, :visits).find(@place.id)

          render json: serialize_place(@place), status: :created
        else
          render json: { errors: @place.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @place.update(place_params)
          set_tags if params[:place][:tag_ids]
          @place = current_api_user.places.includes(:tags, :visits).find(@place.id)

          render json: serialize_place(@place)
        else
          render json: { errors: @place.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @place.destroy!

        head :no_content
      end

      def nearby
        unless params[:latitude].present? && params[:longitude].present?
          return render json: { error: 'latitude and longitude are required' }, status: :bad_request
        end

        results = Places::NearbySearch.new(
          latitude: params[:latitude].to_f,
          longitude: params[:longitude].to_f,
          radius: params[:radius]&.to_f || 0.5,
          limit: params[:limit]&.to_i || 10
        ).call

        render json: { places: results }
      end

      private

      def set_place
        @place = current_api_user.places.includes(:tags, :visits).find(params[:id])
      end

      def place_params
        params.require(:place).permit(:name, :latitude, :longitude, :source, :note, tag_ids: [])
      end

      def tag_ids
        ids = params.dig(:place, :tag_ids)
        Array(ids).compact
      end

      def add_tags
        return if tag_ids.empty?

        tags = current_api_user.tags.where(id: tag_ids)
        @place.tags << tags
      end

      def set_tags
        tag_ids_param = Array(params.dig(:place, :tag_ids)).compact
        tags = current_api_user.tags.where(id: tag_ids_param)
        @place.tags = tags
      end

      def serialize_place(place)
        {
          id: place.id,
          name: place.name,
          latitude: place.lat,
          longitude: place.lon,
          source: place.source,
          note: place.note,
          icon: place.tags.first&.icon,
          color: place.tags.first&.color,
          visits_count: place.visits.count,
          created_at: place.created_at,
          tags: place.tags.map do |tag|
            {
              id: tag.id,
              name: tag.name,
              icon: tag.icon,
              color: tag.color,
              privacy_radius_meters: tag.privacy_radius_meters
            }
          end
        }
      end
    end
  end
end
