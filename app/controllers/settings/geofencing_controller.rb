# frozen_string_literal: true

class Settings::GeofencingController < ApplicationController
  include SafeTimestampParser

  before_action :authenticate_user!

  def show
    @places = current_user.places.geofences.order(:name)
    @webhooks_allowed = WebhookPolicy.new(current_user, Webhook).create?
    @webhooks = current_user.webhooks.order(created_at: :desc)
    @events = filtered_events.page(params[:page]).per(25)
  end

  private

  def filtered_events
    current_user.scoped_geofence_events.includes(:place, :webhook_deliveries)
                .order(occurred_at: :desc, id: :desc)
                .for_place(params[:place_id])
                .occurred_within_days(parse_time_param(params[:start_at]), parse_time_param(params[:end_at]))
  end
end
