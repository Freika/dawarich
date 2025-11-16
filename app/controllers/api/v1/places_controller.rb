# frozen_string_literal: true

module Api
  module V1
    class PlacesController < ApiController
      before_action :set_place, only: [:show, :update, :destroy]

      def index
        @places = policy_scope(Place).includes(:tags)
        @places = @places.with_tags(params[:tag_ids]) if params[:tag_ids].present?
        
        render json: Api::PlaceSerializer.new(@places).serialize
      end

      def show
        authorize @place
        render json: Api::PlaceSerializer.new(@place).serialize
      end

      def create
        @place = current_api_user.places.build(place_params)
        authorize @place

        if @place.save
          add_tags if tag_ids.present?
          render json: Api::PlaceSerializer.new(@place).serialize, status: :created
        else
          render json: { errors: @place.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        authorize @place

        if @place.update(place_params)
          sync_tags if params[:place][:tag_ids]
          render json: Api::PlaceSerializer.new(@place).serialize
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

      def sync_tags
        tag_ids_param = Array(params.dig(:place, :tag_ids)).compact
        tags = current_api_user.tags.where(id: tag_ids_param)
        @place.tags = tags
      end
    end
  end
end
