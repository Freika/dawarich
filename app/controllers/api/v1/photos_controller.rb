# frozen_string_literal: true

class Api::V1::PhotosController < ApiController
  def index
    @photos = Rails.cache.fetch("photos_#{params[:start_date]}_#{params[:end_date]}", expires_in: 1.day) do
      Immich::RequestPhotos.new(current_api_user, start_date: params[:start_date], end_date: params[:end_date]).call
    end.reject { |photo| photo['type'].downcase == 'video' }

    render json: @photos, status: :ok
  end

  def thumbnail
    response = Rails.cache.fetch("photo_thumbnail_#{params[:id]}", expires_in: 1.day) do
      HTTParty.get(
        "#{current_api_user.settings['immich_url']}/api/assets/#{params[:id]}/thumbnail?size=preview",
        headers: {
          'x-api-key' => current_api_user.settings['immich_api_key'],
          'accept' => 'application/octet-stream'
        }
      )
    end

    if response.success?
      send_data(
        response.body,
        type: 'image/jpeg',
        disposition: 'inline',
        status: :ok
      )
    else
      Rails.logger.error "Failed to fetch thumbnail: #{response.code} - #{response.body}"
      render json: { error: 'Failed to fetch thumbnail' }, status: response.code
    end
  end
end
