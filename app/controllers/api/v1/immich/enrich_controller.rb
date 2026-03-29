# frozen_string_literal: true

class Api::V1::Immich::EnrichController < ApiController
  before_action :require_pro_api!

  def scan
    result = Immich::EnrichScan.new(
      current_api_user,
      start_date: params[:start_date],
      end_date: params[:end_date],
      tolerance: params[:tolerance] || Immich::EnrichScan::DEFAULT_TOLERANCE
    ).call

    render json: result
  end

  def create
    assets = params[:assets] || []
    result = Immich::EnrichPhotos.new(current_api_user, assets.map(&:to_unsafe_h)).call

    render json: result
  end
end
