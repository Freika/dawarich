# frozen_string_literal: true

class UserDevicesController < ApplicationController
  before_action :authenticate_user!

  def destroy
    current_user.user_devices.find(params[:id]).destroy!
    redirect_back fallback_location: settings_general_index_path, notice: 'Device revoked.'
  end
end
