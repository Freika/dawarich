# frozen_string_literal: true

class Api::V1::PhotosController < ApiController
  def index
    @photos = Rails.cache.fetch("photos_#{params[:start_date]}_#{params[:end_date]}", expires_in: 1.day) do
      Immich::RequestPhotos.new(current_api_user, start_date: params[:start_date], end_date: params[:end_date]).call
    end

    render json: @photos, status: :ok
  end
end
