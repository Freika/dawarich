# frozen_string_literal: true

class Settings::IntegrationsController < ApplicationController
  MAX_FLIGHT_IMPORT_SIZE = 10.megabytes

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update import_flights]
  before_action :require_pro!, only: %i[update import_flights]

  def index
    @pro_required = !current_user.full_access?
  end

  def update
    result = Settings::Update.new(
      current_user,
      settings_params,
      refresh_photos_cache: params[:refresh_photos_cache].present?
    ).call

    flash[:notice] = result[:notices].join('. ') if result[:notices].any?
    flash[:alert] = result[:alerts].join('. ') if result[:alerts].any?

    redirect_to settings_integrations_path
  end

  def import_flights
    file = params[:file]
    if file.blank?
      redirect_to settings_integrations_path, alert: 'Please select an AirTrail JSON file to import.'
      return
    end

    unless valid_flight_import_file?(file)
      redirect_to settings_integrations_path,
                  alert: 'Invalid file. Please upload a .json file (max 10 MB).'
      return
    end

    Flights::ImportFromJsonJob.perform_later(current_user.id, file.read)

    redirect_to settings_integrations_path,
                notice: 'Flight import started. You will be notified when it completes.'
  end

  private

  def valid_flight_import_file?(file)
    return false if file.size > MAX_FLIGHT_IMPORT_SIZE

    json_content_type?(file) || file.original_filename.to_s.downcase.end_with?('.json')
  end

  def json_content_type?(file)
    type = file.content_type.to_s
    type.in?(%w[application/json text/json application/octet-stream]) || type.end_with?('+json')
  end

  def settings_params
    params.require(:settings).permit(
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification,
      :airtrail_url, :airtrail_api_key, :airtrail_skip_ssl_verification
    )
  end
end
