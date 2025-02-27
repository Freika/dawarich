# frozen_string_literal: true

class Settings::SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def index; end

  def subscription_callback
    token = params[:token]

    begin
      decoded_token = JWT.decode(
        token,
        ENV['JWT_SECRET_KEY'],
        true,
        { algorithm: 'HS256' }
      ).first.symbolize_keys

      # Verify this is for the current user
      unless decoded_token[:user_id] == current_user.id
        redirect_to settings_subscriptions_path, alert: 'Invalid subscription update request.'
        return
      end

      current_user.update!(status: decoded_token[:status])

      redirect_to settings_subscriptions_path, notice: 'Your subscription has been updated successfully!'
    rescue JWT::DecodeError
      redirect_to settings_subscriptions_path, alert: 'Failed to verify subscription update.'
    rescue ArgumentError
      redirect_to settings_subscriptions_path, alert: 'Invalid subscription data received.'
    end
  end
end
