# frozen_string_literal: true

class Api::V1::AreasController < ApiController
  before_action :set_area, only: %i[update destroy]

  def index
    @areas = current_api_user.areas

    render json: @areas, status: :ok
  end

  def create
    @area = current_api_user.areas.build(area_params)

    if @area.save
      render json: @area, status: :created
    else
      render json: { errors: @area.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @area.update(area_params)
      render json: @area, status: :ok
    else
      render json: { errors: @area.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @area.destroy!

    render json: { message: 'Area was successfully deleted' }, status: :ok
  end

  private

  def set_area
    @area = current_api_user.areas.find(params[:id])
  end

  def area_params
    params.require(:area).permit(:name, :latitude, :longitude, :radius)
  end
end
