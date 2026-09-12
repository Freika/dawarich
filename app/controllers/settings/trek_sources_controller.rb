# frozen_string_literal: true

class Settings::TrekSourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!
  before_action :require_pro!
  before_action :set_source, only: %i[destroy select_trips import_trips sync]

  def create
    source = current_user.trip_sources.build(source_params.merge(provider: 'trek'))
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
    @selected_identifiers = @source.trips.pluck(:source_identifier)
  rescue Trek::Client::Error => e
    redirect_to settings_integrations_path(service: 'trek'), alert: e.message
  end

  def import_trips
    identifiers = Array(params[:trip_ids]).map(&:to_s).reject(&:blank?).first(100)
    if identifiers.empty?
      return redirect_to select_trips_settings_trek_source_path(@source), alert: t('.select_at_least_one_trip')
    end

    synchronizer = Trek::Sync.new(@source)
    identifiers.each { |identifier| synchronizer.import!(identifier) }
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
