# frozen_string_literal: true

class Trial::WelcomeController < ApplicationController
  CONSUMED_KEY_PREFIX = 'trial_welcome:consumed:'

  before_action :no_store_headers

  def show
    decoded = Subscription::DecodeJwtToken.new(params[:token], expected_purpose: 'trial_welcome').call

    jti = decoded[:jti].to_s
    return redirect_to(new_user_session_path, alert: 'Link invalid. Please sign in.') if jti.blank?

    @user = User.find(decoded[:user_id])

    if user_signed_in? && current_user != @user
      return redirect_to(root_path, alert: 'Another user is already signed in.')
    end

    if token_already_consumed?(jti)
      return redirect_to(helpers.preferred_map_path) if user_signed_in? && current_user == @user

      return redirect_to(new_user_session_path, alert: 'This welcome link has already been used.')
    end

    mark_token_consumed!(jti, decoded[:exp])
    sign_in(@user) unless current_user == @user
    redirect_to helpers.preferred_map_path, notice: welcome_notice(@user)
  rescue JWT::DecodeError
    redirect_to new_user_session_path, alert: 'Link invalid or expired. Please sign in.'
  rescue ActiveRecord::RecordNotFound
    redirect_to new_user_session_path, alert: 'Account no longer exists. Please sign up again.'
  end

  private

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end

  def token_already_consumed?(jti)
    Rails.cache.exist?("#{CONSUMED_KEY_PREFIX}#{jti}")
  end

  def mark_token_consumed!(jti, exp)
    ttl = [(exp.to_i - Time.now.to_i), 60].max
    Rails.cache.write("#{CONSUMED_KEY_PREFIX}#{jti}", true, expires_in: ttl)
  end

  def welcome_notice(user)
    if user.active_until.present?
      "Welcome to Dawarich — your 7-day free trial is active until #{user.active_until.strftime('%B %d, %Y')}."
    else
      'Welcome to Dawarich — your trial is being activated now.'
    end
  end
end
