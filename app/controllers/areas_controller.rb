# frozen_string_literal: true

class AreasController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_area, only: %i[update]

  def create
    @area = current_user.areas.build(area_params)

    if @area.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:success, I18n.t('controllers.areas.created'))
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, @area.errors.full_messages.join(', '))
        end
      end
    end
  end

  def update
    if @area.update(area_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:success, I18n.t('controllers.areas.updated'))
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, @area.errors.full_messages.join(', '))
        end
      end
    end
  end

  private

  def set_area
    @area = current_user.areas.find(params[:id])
  end

  def area_params
    params.permit(:name, :latitude, :longitude, :radius)
  end
end
