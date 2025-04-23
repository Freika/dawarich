# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApiController
  skip_before_action :authenticate_api_key, only: %i[callback]
  def callback
    decoded_token = Subscription::DecodeJwtToken.new(params[:token]).call

    user = User.find(decoded_token[:user_id])
    user.update!(status: decoded_token[:status], active_until: decoded_token[:active_until])

    render json: { message: 'Subscription updated successfully' }
  rescue JWT::DecodeError => e
    Sentry.capture_exception(e)
    render json: { message: 'Failed to verify subscription update.' }, status: :unauthorized
  rescue ArgumentError => e
    Sentry.capture_exception(e)
    render json: { message: 'Invalid subscription data received.' }, status: :unprocessable_entity
  end
end
