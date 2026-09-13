# frozen_string_literal: true

# Deprecated compatibility surface backed by Places. Legacy IDs belong to the
# Area shell, but the returned geometry and all mutations come from its mapped
# canonical Place.
class Api::V1::AreasController < ApiController
  before_action :add_deprecation_headers
  before_action :set_area, only: %i[show update destroy]

  def index
    render json: current_api_user.areas.order(:id).map { |area| adapter.payload(area) }, status: :ok
  end

  def show
    render json: adapter.payload(@area), status: :ok
  end

  def create
    area, place = adapter.create(area_params)
    render json: adapter.payload(area, place), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  def update
    place = adapter.update(@area, area_params)
    render json: adapter.payload(@area, place), status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
  end

  def destroy
    adapter.destroy(@area)
    render json: { message: I18n.t('controllers.api.v1.areas.area_was_successfully_deleted') }, status: :ok
  end

  private

  def set_area
    @area = current_api_user.areas.find(params[:id])
  end

  def adapter
    @adapter ||= Places::LegacyAreaAdapter.new(user: current_api_user)
  end

  def add_deprecation_headers
    response.set_header('Deprecation', 'true')
    response.set_header('Warning', '299 Dawarich "Areas API is deprecated; use /api/v1/places"')
    response.set_header('Link', '<https://dawarich.app/api/v1/places>; rel="successor-version"')
  end

  def area_params
    params.require(:area).permit(:name, :latitude, :longitude, :radius)
  end
end
