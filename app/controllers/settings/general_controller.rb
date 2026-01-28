# frozen_string_literal: true

class Settings::GeneralController < ApplicationController
  before_action :authenticate_user!

  def index; end

  def update
    update_email_settings if params[:digest_emails_enabled].present?

    if current_user.save
      redirect_to settings_general_index_path, notice: 'Settings updated'
    else
      redirect_to settings_general_index_path, alert: 'Failed to update settings'
    end
  end

  private

  def update_email_settings
    current_user.settings['digest_emails_enabled'] = ActiveModel::Type::Boolean.new.cast(params[:digest_emails_enabled])
  end
end
