# frozen_string_literal: true

class Api::V1::UserDevicesController < ApiController
  before_action :authenticate_active_api_user!

  def index
    render json: current_api_user.user_devices
  end

  def create
    device = current_api_user.user_devices.find_by(device_id: device_params[:device_id])
    if device
      device.update!(device_params.merge(last_seen_at: Time.current))
      render json: device, status: :ok
    else
      device = current_api_user.user_devices.create!(device_params.merge(last_seen_at: Time.current))
      render json: device, status: :created
    end
  end

  def destroy
    current_api_user.user_devices.find(params[:id]).destroy!
    head :no_content
  end

  private

  def device_params
    params.require(:user_device).permit(:platform, :device_id, :device_name, :push_token, :app_version)
  end
end
