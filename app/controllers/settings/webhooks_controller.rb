# frozen_string_literal: true

class Settings::WebhooksController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_webhook, except: :create
  rate_limit to: 5, within: 1.minute, only: :test, by: -> { @webhook.id },
             with: -> { respond_with_flash(t('settings.webhooks.test.rate_limited'), status: :too_many_requests) },
             unless: -> { DawarichSettings.self_hosted? }

  def show
    @deliveries = @webhook.webhook_deliveries.includes(geofence_event: :place).order(created_at: :desc).limit(50)
  end

  def create
    @webhook = current_user.webhooks.new(webhook_params)
    authorize @webhook

    if @webhook.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to settings_geofencing_path, notice: t('.created') }
      end
    else
      render :form_errors, formats: :turbo_stream, status: :unprocessable_content
    end
  end

  def update
    if @webhook.update(webhook_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to settings_geofencing_path, notice: t('.updated') }
      end
    else
      render :form_errors, formats: :turbo_stream, status: :unprocessable_content
    end
  end

  def destroy
    @webhook.destroy!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to settings_geofencing_path, notice: t('.deleted') }
    end
  end

  def test
    message = GeofenceEvents::SendTest.call(@webhook) ? t('.sent') : t('.no_place')
    respond_with_flash(message)
  end

  def regenerate_secret
    @webhook.regenerate_secret!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to settings_geofencing_path }
    end
  end

  def retry_delivery
    delivery = @webhook.webhook_deliveries.status_failure.find(params[:delivery_id])
    delivery.update!(status: :pending, error_message: nil)
    Webhooks::DeliverJob.perform_later(delivery.id)
    respond_with_flash(t('.queued'))
  end

  private

  def set_webhook
    @webhook = current_user.webhooks.find(params[:id])
    authorize @webhook
  end

  def webhook_params
    params.require(:webhook).permit(:name, :url, :active, event_types: [], place_ids: []).tap do |permitted|
      permitted[:place_ids] = permitted[:place_ids].compact_blank.map(&:to_i) if permitted.key?(:place_ids)
    end
  end

  def respond_with_flash(message, status: :ok)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:notice, message), status: }
      format.html { redirect_back fallback_location: settings_geofencing_path, notice: message }
    end
  end
end
