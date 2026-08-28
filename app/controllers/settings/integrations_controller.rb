# frozen_string_literal: true

class Settings::IntegrationsController < ApplicationController
  FLASH_MESSAGE_BYTES = 512
  MAX_FLIGHT_IMPORT_SIZE = 10.megabytes

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update import_flights]
  before_action :require_pro!, only: %i[update import_flights]

  def index
    @pro_required = !current_user.full_access?
    return if @pro_required

    @services = available_services
    @service = params[:service].presence_in(@services) || @services.first
    @statuses = Integrations::Status.for(current_user)
    @flight_import_formats = Flights::Parsers::Registry.formats
    @flight_import_accept = Flights::Parsers::Registry.accept_attribute

    prepare_geocoding if @service == 'geocoding'
  end

  def update
    result = Settings::Update.new(
      current_user,
      settings_params,
      refresh_photos_cache: params[:refresh_photos_cache].present?
    ).call

    flash[:notice] = flash_message(result[:notices]) if result[:notices].any?
    flash[:alert] = flash_message(result[:alerts]) if result[:alerts].any?

    redirect_to settings_integrations_path(service: params[:service].presence)
  end

  def import_flights
    file = params[:file]
    if file.blank?
      redirect_to settings_integrations_path(service: 'airtrail'),
                  alert: 'Please select a flight export file to import.'
      return
    end

    unless valid_flight_import_file?(file)
      extensions = Flights::Parsers::Registry.accepted_extensions.join(', ')
      redirect_to settings_integrations_path(service: 'airtrail'),
                  alert: "Invalid file. Please upload a supported flight export (#{extensions}, max 10 MB)."
      return
    end

    format = params[:format].presence
    format = nil if format == 'auto'

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.to_io,
      filename: file.original_filename,
      content_type: file.content_type
    )
    Flights::ImportFromFileJob.perform_later(current_user.id, blob.id, format)

    redirect_to settings_integrations_path(service: 'airtrail'),
                notice: 'Flight import started. You will be notified when it completes.'
  end

  private

  def flash_message(messages)
    messages.join('. ').truncate_bytes(FLASH_MESSAGE_BYTES)
  end

  def available_services
    return Integrations::Status::SERVICES if DawarichSettings.self_hosted?

    Integrations::Status::PHOTO_SERVICES
  end

  def prepare_geocoding
    @settings_by_provider = current_user.service_settings.service_geocoding.index_by(&:provider)
    @geocoding_config = Geocoding::Config.for(current_user)
  end

  def valid_flight_import_file?(file)
    return false if file.size > MAX_FLIGHT_IMPORT_SIZE

    Flights::Parsers::Registry.supported_format?(
      filename: file.original_filename,
      content_type: file.content_type
    )
  end

  def settings_params
    params.require(:settings).permit(
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification,
      :airtrail_url, :airtrail_api_key, :airtrail_skip_ssl_verification
    )
  end
end
