# frozen_string_literal: true

class Trial::WelcomeController < ApplicationController
  CONSUMED_KEY_PREFIX = 'trial_welcome:consumed:'

  before_action :no_store_headers

  def show
    decoded = Subscription::DecodeJwtToken.new(params[:token], expected_purpose: 'trial_welcome').call

    jti = decoded[:jti].to_s
    if jti.blank?
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.trial.welcome.link_invalid_please_sign_in'))
    end

    @user = User.find(decoded[:user_id])

    if user_signed_in? && current_user != @user
      return redirect_to(root_path, alert: I18n.t('controllers.trial.welcome.another_user_is_already_signed_in'))
    end

    consumed = !mark_token_consumed!(jti, decoded[:exp])
    if consumed
      return redirect_to(helpers.preferred_map_path) if user_signed_in? && current_user == @user

      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.trial.welcome.this_welcome_link_has_already_been_used'))
    end

    log_event('trial_welcome_consumed', user_id: @user.id, jti: jti, variant: @user.signup_variant)

    sign_in(@user) unless current_user == @user
    redirect_to helpers.preferred_map_path, notice: welcome_notice(@user)
  rescue JWT::DecodeError
    redirect_to new_user_session_path, alert: I18n.t('controllers.trial.welcome.link_invalid_or_expired_please_sign_in')
  rescue ActiveRecord::RecordNotFound
    redirect_to new_user_session_path,
                alert: I18n.t('controllers.trial.welcome.account_no_longer_exists_please_sign_up_again')
  end

  private

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Referrer-Policy'] = 'no-referrer'
  end

  def mark_token_consumed!(jti, exp)
    ttl = [(exp.to_i - Time.current.to_i), 60].max
    Rails.cache.write("#{CONSUMED_KEY_PREFIX}#{jti}", true, expires_in: ttl, unless_exist: true)
  end

  def welcome_notice(user)
    if user.active_until.present?
      I18n.t(
        'controllers.trial.welcome.trial_active_until',
        date: I18n.l(user.active_until.to_date, format: :long)
      )
    else
      I18n.t('controllers.trial.welcome.trial_activating')
    end
  end

  def log_event(name, **payload)
    Rails.logger.info({ event: name, **payload }.to_json)
  end
end
