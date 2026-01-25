# frozen_string_literal: true

class Settings::GeneralController < ApplicationController
  before_action :authenticate_user!

  def index
    @timezones = ActiveSupport::TimeZone.all.map { |tz| [tz.to_s, tz.name] }
    @current_timezone = current_user.timezone
  end

  def update
    update_timezone if params[:timezone].present?
    update_email_settings if params[:digest_emails_enabled].present?

    if current_user.save
      handle_success_response
    else
      handle_error_response
    end
  end

  private

  def update_timezone
    current_user.timezone = params[:timezone]
  end

  def update_email_settings
    current_user.settings['digest_emails_enabled'] = ActiveModel::Type::Boolean.new.cast(params[:digest_emails_enabled])
  end

  def handle_success_response
    respond_to do |format|
      format.html { redirect_to settings_general_index_path, notice: 'Settings updated' }
      format.json { render json: { success: true, timezone: current_user.timezone } }
    end
  end

  def handle_error_response
    respond_to do |format|
      format.html { redirect_to settings_general_index_path, alert: 'Failed to update settings' }
      format.json do
        render json: { success: false, errors: current_user.errors.full_messages },
               status: :unprocessable_entity
      end
    end
  end
end
