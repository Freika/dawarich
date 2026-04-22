# frozen_string_literal: true

class WebhooksController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_webhook, only: %i[show edit update destroy test regenerate_secret]

  def index
    authorize Webhook
    @webhooks = current_user.webhooks.order(created_at: :desc)
  end

  def show
    authorize @webhook
    @deliveries = @webhook.webhook_deliveries.order(created_at: :desc).limit(50)

    reveal = session.delete(:webhook_secret_reveal)
    @reveal_secret = reveal && reveal['id'] == @webhook.id ? reveal['secret'] : nil
  end

  def new
    @webhook = current_user.webhooks.new
    authorize @webhook
  end

  def create
    @webhook = current_user.webhooks.new(webhook_params)
    authorize @webhook

    if @webhook.save
      session[:webhook_secret_reveal] = { 'id' => @webhook.id, 'secret' => @webhook.secret }
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to webhook_path(@webhook) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @webhook
  end

  def update
    authorize @webhook

    if @webhook.update(webhook_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to webhooks_path }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @webhook
    @webhook.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to webhooks_path }
    end
  end

  def test
    authorize @webhook, :test?
    area = pick_testable_area_for(@webhook)
    return redirect_to(webhook_path(@webhook), alert: 'Create an area first to test.') if area.nil?

    event_type = @webhook.event_types.include?(0) ? :enter : :leave
    event = GeofenceEvent.create!(
      user: current_user,
      area: area,
      event_type: event_type,
      source: :native_app,
      occurred_at: Time.current,
      received_at: Time.current,
      lonlat: "POINT(#{area.longitude} #{area.latitude})",
      metadata: { test: true },
      synthetic: true
    )
    delivery = WebhookDelivery.create!(webhook: @webhook, geofence_event: event, status: :pending)
    Webhooks::DeliverJob.perform_later(delivery.id)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:notice, 'Test webhook sent.') }
      format.html { redirect_to webhook_path(@webhook), notice: 'Test sent.' }
    end
  end

  def regenerate_secret
    authorize @webhook, :update?
    @webhook.regenerate_secret!
    redirect_to edit_webhook_path(@webhook), notice: 'Secret regenerated.'
  end

  private

  def set_webhook
    @webhook = current_user.webhooks.find(params[:id])
  end

  def webhook_params
    params.require(:webhook).permit(:name, :url, :active, event_types: [], area_ids: [])
  end

  def pick_testable_area_for(webhook)
    scope = current_user.areas
    scope = scope.where(id: webhook.area_ids) if webhook.area_ids.present?
    scope.first
  end
end
