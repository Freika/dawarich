# frozen_string_literal: true

class Api::V1::PhotosController < ApiController
  def index
    @photos = Rails.cache.fetch("photos_#{params[:start_date]}_#{params[:end_date]}", expires_in: 1.day) do
      Photos::Request.new(current_api_user, start_date: params[:start_date], end_date: params[:end_date]).call
    end

    render json: @photos, status: :ok
  end

  def thumbnail
    response = fetch_cached_thumbnail
    handle_thumbnail_response(response)
  end

  private

  def fetch_cached_thumbnail
    Rails.cache.fetch("photo_thumbnail_#{params[:id]}", expires_in: 1.day) do
      HTTParty.get(
        "#{current_api_user.settings['immich_url']}/api/assets/#{params[:id]}/thumbnail?size=preview",
        headers: {
          'x-api-key' => current_api_user.settings['immich_api_key'],
          'accept' => 'application/octet-stream'
        }
      )
    end
  end

  def handle_thumbnail_response(response)
    if response.success?
      send_data(response.body, type: 'image/jpeg', disposition: 'inline', status: :ok)
    else
      render json: { error: 'Failed to fetch thumbnail' }, status: response.code
    end
  end
end
