# frozen_string_literal: true

class Api::V1::WebhooksController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_pro_api!, except: %i[index show]
  before_action :set_webhook, only: %i[show update destroy test regenerate_secret]

  def index
    render json: current_api_user.webhooks.order(created_at: :desc)
  end

  def show
    render json: @webhook
  end

  def create
    webhook = current_api_user.webhooks.new(webhook_params)

    validation = Webhooks::UrlValidator.call(webhook.url.to_s)
    return render json: { error: "Invalid URL: #{validation}" }, status: :unprocessable_entity if validation != :ok

    if webhook.save
      render json: webhook.as_json.merge(secret: webhook.secret), status: :created
    else
      render json: { errors: webhook.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @webhook.update(webhook_params)
      render json: @webhook
    else
      render json: { errors: @webhook.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @webhook.destroy!
    head :no_content
  end

  def test
    area = current_api_user.areas.first
    return render(json: { error: 'No areas to test with' }, status: :unprocessable_entity) unless area

    event = GeofenceEvent.create!(
      user: current_api_user, area: area, event_type: :enter, source: :native_app,
      occurred_at: Time.current, received_at: Time.current,
      lonlat: "POINT(#{area.longitude} #{area.latitude})",
      metadata: { test: true }
    )
    delivery = WebhookDelivery.create!(webhook: @webhook, geofence_event: event, status: :pending)
    Webhooks::DeliverJob.perform_later(delivery.id)
    render json: { delivery_id: delivery.id }, status: :accepted
  end

  def regenerate_secret
    @webhook.regenerate_secret!
    render json: { secret: @webhook.secret }
  end

  private

  def set_webhook
    @webhook = current_api_user.webhooks.find(params[:id])
  end

  def webhook_params
    params.require(:webhook).permit(:name, :url, :active, event_types: [], area_ids: [])
  end
end
