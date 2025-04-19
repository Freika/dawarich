# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_non_self_hosted!

  # rubocop:disable Metrics/MethodLength
  def callback
    token = params[:token]

    begin
      decoded_token = Subscription::DecodeJwtToken.new(token).call

      unless decoded_token[:user_id] == current_user.id
        render json: { message: 'Invalid subscription update request.' }, status: :unauthorized
        return
      end

      current_user.update!(status: decoded_token[:status], active_until: decoded_token[:active_until])

      render json: { message: 'Subscription updated successfully' }
    rescue JWT::DecodeError => e
      Sentry.capture_exception(e)
      render json: { message: 'Failed to verify subscription update.' }, status: :unauthorized
    rescue ArgumentError => e
      Sentry.capture_exception(e)
      render json: { message: 'Invalid subscription data received.' }, status: :unprocessable_entity
    end
  end
  # rubocop:enable Metrics/MethodLength
end
