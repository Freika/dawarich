# frozen_string_literal: true

class Settings::GeneralController < ApplicationController
  before_action :authenticate_user!

  def index; end

  def update
    update_email_settings
    update_supporter_settings

    if current_user.save
      redirect_to settings_general_index_path, notice: 'Settings updated'
    else
      redirect_to settings_general_index_path, alert: 'Failed to update settings'
    end
  end

  def verify_supporter
    email = params[:supporter_email]&.downcase&.strip

    if email.blank?
      return redirect_to settings_general_index_path, alert: 'Please enter an email address'
    end

    current_user.settings['supporter_email'] = email
    current_user.save!

    # Clear cached verification so we get a fresh result
    verifier = Supporter::VerifyEmail.new(email)
    Rails.cache.delete(verifier.cache_key)

    if current_user.reload.supporter?
      redirect_to settings_general_index_path,
                  notice: "Verified! Thank you for supporting Dawarich via #{current_user.supporter_platform&.titleize}."
    else
      redirect_to settings_general_index_path,
                  alert: 'Email not found in supporter list. Make sure you\'re using the same email as your donation platform.'
    end
  end

  private

  def update_email_settings
    if params.key?(:digest_emails_enabled)
      current_user.settings['digest_emails_enabled'] = ActiveModel::Type::Boolean.new.cast(params[:digest_emails_enabled])
    end
    if params.key?(:news_emails_enabled)
      current_user.settings['news_emails_enabled'] = ActiveModel::Type::Boolean.new.cast(params[:news_emails_enabled])
    end
  end

  def update_supporter_settings
    current_user.settings['supporter_email'] = params[:supporter_email] if params.key?(:supporter_email)
    current_user.settings['show_supporter_badge'] = ActiveModel::Type::Boolean.new.cast(params[:show_supporter_badge]) if params.key?(:show_supporter_badge)
  end
end
