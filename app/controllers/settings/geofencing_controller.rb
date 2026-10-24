# frozen_string_literal: true

class Settings::GeofencingController < ApplicationController
  before_action :authenticate_user!

  def show
    @areas = current_user.areas.order(:name)
    @webhooks_allowed = WebhookPolicy.new(current_user, Webhook).create?
    @webhooks = current_user.webhooks.order(created_at: :desc) if @webhooks_allowed
    @events = filtered_events.page(params[:page]).per(25)
  end

  private

  def filtered_events
    events = current_user.geofence_events.real.includes(:area, :webhook_deliveries)
                         .order(occurred_at: :desc, id: :desc)
    events = events.where(area_id: params[:area_id]) if params[:area_id].present?
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
