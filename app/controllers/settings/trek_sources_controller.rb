# frozen_string_literal: true

class Settings::TrekSourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!
  before_action :require_pro!
  before_action :set_source, only: %i[destroy select_trips import_trips sync]

  def create
    attributes = source_params.to_h.symbolize_keys
    source = current_user.trip_sources.find_or_initialize_by(
      provider: 'trek', base_url: attributes[:base_url].to_s.strip.chomp('/')
    )
    if source.persisted? && source.importing?
      return redirect_to settings_integrations_path(service: 'trek'),
                         alert: t('settings.trek_sources.sync.source_importing')
    end

    connection_attributes = { api_key: attributes[:api_key], status: :active, last_error: nil }
    source.assign_attributes(connection_attributes)
    unless source.valid?
      return redirect_to settings_integrations_path(service: 'trek'), alert: source.errors.full_messages.to_sentence
    end

    Trek::Client.new(source).trips
    if source.persisted?
      source.reload
      source.with_lock do
        return source_importing_redirect if source.importing?

        source.assign_attributes(connection_attributes)
        source.save!
      end
    else
      source.save!
    end
    redirect_to select_trips_settings_trek_source_path(source), notice: t('.connected_choose_trips')
  rescue Trek::Client::Error => e
    redirect_to settings_integrations_path(service: 'trek'), alert: e.message
  end

  def select_trips
    return source_disabled_redirect unless @source.active?
    return source_importing_redirect if @source.importing?

    @remote_trips = Trek::Client.new(@source).trips
    @selected_identifiers = @source.trips.source_active.pluck(:source_identifier)
  rescue Trek::Client::Error => e
    Trek::Sync.new(@source).record_error!(e)
    redirect_to settings_integrations_path(service: 'trek'), alert: e.message
  end

  def import_trips
    return source_disabled_redirect unless @source.active?
    return source_importing_redirect if @source.importing?

    identifiers = Array(params[:trip_ids]).map(&:to_s).reject(&:blank?).uniq
    if identifiers.empty?
      @source.with_lock do
        @source.update!(selection_token: SecureRandom.uuid, importing: false)
        @source.trips.source_active.update_all(
          source_status: Trip.source_statuses.fetch('stopped'), source_synced_at: Time.current
        )
      end
      return redirect_to settings_integrations_path(service: 'trek'), notice: t('.no_trips_selected')
    end

    client = Trek::Client.new(@source)
    remote_trips = client.trips
    available_identifiers = remote_trips.filter_map do |trip|
      trip.fetch('id').to_s if trip['archived'] != true && trip['start_date'].present? && trip['end_date'].present?
    end
    identifiers &= available_identifiers
    if identifiers.empty?
      return redirect_to select_trips_settings_trek_source_path(@source), alert: t('.select_at_least_one_dated_trip')
    end

    token = nil
    @source.with_lock do
      next if !@source.active? || @source.importing?

      token = SecureRandom.uuid
      @source.update!(selection_token: token, importing: true)
    end
    return source_importing_redirect unless token

    Trek::ImportTripsJob.perform_later(@source.id, identifiers, token)
    redirect_to settings_integrations_path(service: 'trek'), notice: t('.trips_are_now_syncing')
  rescue Trek::Client::Error => e
    Trek::Sync.new(@source).record_error!(e)
    redirect_to settings_integrations_path(service: 'trek'), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to select_trips_settings_trek_source_path(@source), alert: e.message
  end

  def sync
    return redirect_to settings_integrations_path(service: 'trek'), alert: t('.source_disabled') unless @source.active?
    return redirect_to settings_integrations_path(service: 'trek'), alert: t('.source_importing') if @source.importing?

    Trek::SyncJob.perform_later(@source.id)
    redirect_to settings_integrations_path(service: 'trek'), notice: t('.sync_queued')
  end

  def destroy
    return source_importing_redirect if @source.importing?

    TripSource.transaction do
      @source.trips.find_each do |trip|
        trip.update!(trip_source: nil, source_status: :stopped)
      end
      @source.destroy!
    end
    redirect_to settings_integrations_path(service: 'trek'), notice: t('.source_removed_trips_kept')
  end

  private

  def set_source
    @source = current_user.trip_sources.find_by!(id: params[:id], provider: 'trek')
  end

  def source_params
    params.require(:trip_source).permit(:base_url, :api_key)
  end

  def source_disabled_redirect
    redirect_to settings_integrations_path(service: 'trek'), alert: t('settings.trek_sources.sync.source_disabled')
  end

  def source_importing_redirect
    redirect_to settings_integrations_path(service: 'trek'), alert: t('settings.trek_sources.sync.source_importing')
  end
end
