# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApiController
  skip_before_action :authenticate_api_key, only: %i[callback]

  def callback
    decoded_token = Subscription::DecodeJwtToken.new(params[:token]).call

    user = User.find(decoded_token[:user_id])
    attrs = { status: decoded_token[:status], active_until: decoded_token[:active_until] }

    if decoded_token[:plan].present?
      unless User.plans.key?(decoded_token[:plan])
        return render json: { message: "Invalid plan: #{decoded_token[:plan]}" }, status: :unprocessable_content
      end

      attrs[:plan] = decoded_token[:plan]
    end

    user.update!(attrs)

    render json: { message: 'Subscription updated successfully' }
  rescue JWT::DecodeError => e
    ExceptionReporter.call(e)
    render json: { message: 'Failed to verify subscription update.' }, status: :unauthorized
  rescue ArgumentError => e
    ExceptionReporter.call(e)
    render json: { message: 'Invalid subscription data received.' }, status: :unprocessable_content
  end
end
