# frozen_string_literal: true

class Settings::IntegrationsController < ApplicationController
  FLASH_MESSAGE_BYTES = 512

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update]
  before_action :require_pro!, only: %i[update]

  def index
    return redirect_to admin_settings_path if old_geocoding_link_for_admin?

    @pro_required = !current_user.full_access?
    return if @pro_required

    @services = Integrations::Status::SERVICES
    @service = params[:service].presence_in(@services) || @services.first
    @statuses = Integrations::Status.for(current_user)
    @integration_result ||= session.delete(:integration_feedback)
    @trek_sources = current_user.trip_sources.where(provider: 'trek').order(:created_at) if @service == 'trek'
  end

  def update
    return update_connection if params[:connection_action].present?

    result = Settings::Update.new(
      current_user,
      settings_params,
      refresh_photos_cache: params[:refresh_photos_cache].present?
    ).call

    flash[:notice] = flash_message(result[:notices]) if result[:notices].any?
    flash[:alert] = flash_message(result[:alerts]) if result[:alerts].any?

    redirect_to settings_integrations_path(service: params[:service].presence)
  end

  private

  CONNECTION_ACTIONS = %w[save test save_and_test].freeze
  CONNECTION_FIELDS = {
    'immich' => %w[immich_url immich_api_key immich_skip_ssl_verification],
    'photoprism' => %w[photoprism_url photoprism_api_key photoprism_skip_ssl_verification],
    'airtrail' => %w[airtrail_url airtrail_api_key airtrail_skip_ssl_verification],
    'teslamate' => %w[teslamate_url teslamate_username teslamate_password teslamate_api_token
                      teslamate_skip_ssl_verification]
  }.freeze

  def update_connection
    service = params[:service].to_s
    action = params[:connection_action].to_s
    return head :bad_request unless CONNECTION_ACTIONS.include?(action) && CONNECTION_FIELDS.key?(service)

    draft = settings_params.slice(*CONNECTION_FIELDS.fetch(service)).to_h
    result = Settings::Update.new(current_user, draft, connection_action: action, service: service).call
    connection = result.fetch(:connection_results, {}).fetch(service, {})
    outcome = if !result[:success]
                'validation_failed'
              elsif action == 'save'
                'saved_untested'
              elsif action == 'test'
                connection[:success] ? 'tested_ok' : 'tested_failed'
              else
                connection[:success] ? 'saved_ok' : 'saved_failed'
              end
    @integration_result = { 'service' => service, 'outcome' => outcome,
                            'reason' => connection.fetch(:reason, 'check_settings') }
    if action == 'test' || !result[:success]
      current_user.settings = current_user.settings_hash.merge(draft)
      index
      render :index, status: result[:success] ? :ok : :unprocessable_entity
    else
      session[:integration_feedback] = @integration_result
      redirect_to settings_integrations_path(service: service)
    end
  end

  def flash_message(messages)
    messages.join('. ').truncate_bytes(FLASH_MESSAGE_BYTES)
  end

  def old_geocoding_link_for_admin?
    params[:service] == 'geocoding' && current_user.admin? && DawarichSettings.self_hosted?
  end

  def settings_params
    params.require(:settings).permit(
      :immich_url, :immich_api_key, :immich_skip_ssl_verification,
      :photoprism_url, :photoprism_api_key, :photoprism_skip_ssl_verification,
      :airtrail_url, :airtrail_api_key, :airtrail_skip_ssl_verification,
      :teslamate_url, :teslamate_username, :teslamate_password, :teslamate_api_token,
      :teslamate_skip_ssl_verification
    )
  end
end
