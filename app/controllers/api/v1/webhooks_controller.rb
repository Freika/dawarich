# frozen_string_literal: true

class Api::V1::WebhooksController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_pro_api!, except: :destroy
  before_action :set_webhook, only: %i[show update destroy test regenerate_secret]

  def index
    render json: current_api_user.webhooks.order(created_at: :desc)
  end

  def show
    render json: @webhook
  end

  def create
    webhook = current_api_user.webhooks.new(webhook_params)

    if webhook.save
      render json: webhook.as_json.merge('secret' => webhook.secret), status: :created
    else
      render json: { errors: webhook.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @webhook.update(webhook_params)
      render json: @webhook
    else
      render json: { errors: @webhook.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @webhook.destroy!
    head :no_content
  end

  def test
    delivery = GeofenceEvents::SendTest.call(@webhook)
    return render json: { error: 'no_area' }, status: :unprocessable_content unless delivery

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
