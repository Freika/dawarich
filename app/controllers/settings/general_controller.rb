# frozen_string_literal: true

class Settings::GeneralController < ApplicationController
  before_action :authenticate_user!

  def index
    @timezones = ActiveSupport::TimeZone.all.map { |tz| [tz.to_s, tz.name] }
    @current_timezone = current_user.timezone
  end

  def update
    current_user.timezone = params[:timezone]

    if current_user.save
      handle_success_response
    else
      handle_error_response
    end
  end

  private

  def handle_success_response
    respond_to do |format|
      format.html { redirect_to settings_general_index_path, notice: 'Timezone updated' }
      format.json { render json: { success: true, timezone: current_user.timezone } }
    end
  end

  def handle_error_response
    respond_to do |format|
      format.html { redirect_to settings_general_index_path, alert: 'Failed to update timezone' }
      format.json do
        render json: { success: false, errors: current_user.errors.full_messages },
               status: :unprocessable_entity
      end
    end
  end
end
