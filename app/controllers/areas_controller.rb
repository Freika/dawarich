# frozen_string_literal: true

class AreasController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!

  def create
    @area = current_user.areas.build(area_params)

    if @area.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:success, 'Area created successfully!')
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

  def area_params
    params.permit(:name, :latitude, :longitude, :radius)
  end
end
