# frozen_string_literal: true

class VideoExportsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :require_video_service
  before_action :set_video_export, only: %i[destroy]

  def index
    @video_exports = current_user.video_exports
                                 .with_attached_file
                                 .order(created_at: :desc)
                                 .page(params[:page])
  end

  def destroy
    @video_export.destroy

    redirect_to video_exports_url, notice: 'Video export was successfully deleted.', status: :see_other
  end

  private

  def set_video_export
    @video_export = current_user.video_exports.find(params[:id])
  end

  def require_video_service
    return if DawarichSettings.video_service_enabled?

    redirect_to root_path, alert: 'Video service is not available.'
  end
end
