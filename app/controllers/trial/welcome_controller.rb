# frozen_string_literal: true

class Trial::WelcomeController < ApplicationController
  include ApplicationHelper

  CONSUMED_KEY_PREFIX = 'trial_welcome:consumed:'
  # Manager must issue tokens with purpose: 'trial_welcome' and a jti claim.
  # We enforce both here and single-use via Redis to prevent replay if the
  # magic link leaks (email logs, browser history, shared device, proxies).

  before_action :no_store_headers

  def show
    decoded = Subscription::DecodeJwtToken.new(params[:token]).call

    unless decoded[:purpose] == 'trial_welcome'
      return redirect_to(new_user_session_path, alert: 'Link invalid. Please sign in.')
    end

    jti = decoded[:jti].to_s
    if jti.blank?
      return redirect_to(new_user_session_path, alert: 'Link invalid. Please sign in.')
    end

    @user = User.find(decoded[:user_id])

    if user_signed_in? && current_user != @user
      return redirect_to(root_path, alert: 'Another user is already signed in.')
    end

    # A consumed jti for the same signed-in user = reload / meta-refresh /
    # browser back. Skip the flash (user already saw it on first visit) and
    # drop them on the map. For a different or no current_user, treat as a
    # genuine replay attempt.
    if token_already_consumed?(jti)
      return redirect_to(preferred_map_path) if user_signed_in? && current_user == @user

      return redirect_to(new_user_session_path, alert: 'This welcome link has already been used.')
    end

    mark_token_consumed!(jti, decoded[:exp])
    sign_in(@user) unless current_user == @user
    redirect_to preferred_map_path, notice: welcome_notice(@user)
  rescue JWT::DecodeError, ActiveRecord::RecordNotFound
    redirect_to new_user_session_path, alert: 'Link expired. Please sign in.'
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
