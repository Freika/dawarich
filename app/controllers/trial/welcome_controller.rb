# frozen_string_literal: true

class Trial::WelcomeController < ApplicationController
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
    if jti.blank? || token_already_consumed?(jti)
      return redirect_to(new_user_session_path, alert: 'This welcome link has already been used.')
    end

    user = User.find(decoded[:user_id])

    if user_signed_in? && current_user != user
      return redirect_to(root_path, alert: 'Another user is already signed in.')
    end

    mark_token_consumed!(jti, decoded[:exp])
    sign_in(user) unless current_user == user
    @user = user
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
end
