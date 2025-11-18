# frozen_string_literal: true

module Api
  module V1
    class PlacesController < ApiController
      before_action :set_place, only: [:show, :update, :destroy]

      def index
        @places = policy_scope(Place).includes(:tags, :visits)
        @places = @places.with_tags(params[:tag_ids]) if params[:tag_ids].present?
        @places = @places.without_tags if params[:untagged] == 'true'

        render json: @places.map { |place| serialize_place(place) }
      end

      def show
        authorize @place

        render json: serialize_place(@place)
      end

      def create
        @place = current_api_user.places.build(place_params)

        authorize @place

        if @place.save
          add_tags if tag_ids.present?
          render json: serialize_place(@place), status: :created
        else
          render json: { errors: @place.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        authorize @place

        if @place.update(place_params)
          set_tags if params[:place][:tag_ids]
          render json: serialize_place(@place)
        else
          render json: { errors: @place.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @place

        @place.destroy!

        head :no_content
      end

      def nearby
        authorize Place, :nearby?

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
        @place = current_api_user.places.find(params[:id])
      end

      def place_params
        params.require(:place).permit(:name, :latitude, :longitude, :source)
      end

      def tag_ids
        params.dig(:place, :tag_ids) || []
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
          latitude: place.latitude,
          longitude: place.longitude,
          source: place.source,
          icon: place.tags.first&.icon,
          color: place.tags.first&.color,
          visits_count: place.visits.count,
          created_at: place.created_at,
          tags: place.tags.map do |tag|
            {
              id: tag.id,
              name: tag.name,
              icon: tag.icon,
              color: tag.color
            }
          end
        }
      end
    end
  end
end
