# frozen_string_literal: true

class Settings::GeofencingController < ApplicationController
  before_action :authenticate_user!

  def show
    @places = current_user.places.geofences.order(:name)
    @webhooks_allowed = WebhookPolicy.new(current_user, Webhook).create?
    @webhooks = current_user.webhooks.order(created_at: :desc)
    @events = filtered_events.page(params[:page]).per(25)
  end

  private

  def filtered_events
    events = current_user.geofence_events.real.includes(:place, :webhook_deliveries)
                         .order(occurred_at: :desc, id: :desc)
    events = events.where(place_id: params[:place_id]) if params[:place_id].present?
    events = events.where(occurred_at: current_user.data_window_start..) if current_user.plan_restricted?
    from = parse_day(params[:start_at])
    to = parse_day(params[:end_at])
    events = events.where(occurred_at: from.beginning_of_day..) if from
    events = events.where(occurred_at: ..to.end_of_day) if to
    events
  end

  def parse_day(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
