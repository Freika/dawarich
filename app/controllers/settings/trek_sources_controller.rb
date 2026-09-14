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
    source.assign_attributes(api_key: attributes[:api_key], status: :active, last_error: nil)
    unless source.valid?
      return redirect_to settings_integrations_path(service: 'trek'), alert: source.errors.full_messages.to_sentence
    end

    Trek::Client.new(source).trips
    source.save!
    redirect_to select_trips_settings_trek_source_path(source), notice: t('.connected_choose_trips')
  rescue Trek::Client::Error => e
    redirect_to settings_integrations_path(service: 'trek'), alert: e.message
  end

  def select_trips
    @remote_trips = Trek::Client.new(@source).trips
    @selected_identifiers = @source.trips.source_active.pluck(:source_identifier)
  rescue Trek::Client::Error => e
    redirect_to settings_integrations_path(service: 'trek'), alert: e.message
  end

  def import_trips
    identifiers = Array(params[:trip_ids]).map(&:to_s).reject(&:blank?).uniq
    if identifiers.empty?
      return redirect_to select_trips_settings_trek_source_path(@source), alert: t('.select_at_least_one_trip')
    end
    if identifiers.size > 100
      return redirect_to select_trips_settings_trek_source_path(@source), alert: t('.too_many_trips')
    end

    client = Trek::Client.new(@source)
    remote_trips = client.trips
    available_identifiers = remote_trips.reject { |trip| trip['archived'] == true }.map { |trip| trip.fetch('id').to_s }
    identifiers &= available_identifiers
    if identifiers.empty?
      return redirect_to select_trips_settings_trek_source_path(@source), alert: t('.select_at_least_one_active_trip')
    end

    synchronizer = Trek::Sync.new(@source, client:)
    identifiers.each { |identifier| synchronizer.import!(identifier) }
    @source.trips.source_active.where.not(source_identifier: identifiers).update_all(
      source_status: Trip.source_statuses.fetch('stopped'), source_synced_at: Time.current
    )
    redirect_to settings_integrations_path(service: 'trek'), notice: t('.trips_are_now_syncing')
  rescue Trek::Client::Error, ActiveRecord::RecordInvalid => e
    redirect_to select_trips_settings_trek_source_path(@source), alert: e.message
  end

  def sync
    Trek::SyncJob.perform_later(@source.id)
    redirect_to settings_integrations_path(service: 'trek'), notice: t('.sync_queued')
  end

  def destroy
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
end
