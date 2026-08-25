# frozen_string_literal: true

# Receives videos the browser has already rendered. The MP4 arrives as an
# Active Storage signed id from a direct upload, so the request body stays
# small and the file never passes through a Rails process.
class RouteVideosController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!

  def create
    route_video = current_user.route_videos.new(
      name: route_video_params[:name].presence || I18n.t('controllers.route_videos.untitled'),
      status: :stored,
      settings: settings_param
    )
    route_video.file.attach(route_video_params[:file])
    route_video.save!

    render turbo_stream: [
      turbo_stream.prepend('route-video-gallery-list', partial: 'route_videos/route_video',
                                                      locals: { route_video: route_video }),
      stream_flash(:notice, I18n.t('controllers.route_videos.saved'))
    ]
  rescue StandardError => e
    ExceptionReporter.call(e, 'Route video save failed')

    render turbo_stream: stream_flash(:error, I18n.t('controllers.route_videos.failed_to_save')),
           status: :unprocessable_content
  end

  def destroy
    route_video = current_user.route_videos.find(params[:id])
    route_video.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(ActionView::RecordIdentifier.dom_id(route_video))
      end
      format.html do
        redirect_to map_v2_path, notice: I18n.t('controllers.route_videos.deleted'), status: :see_other
      end
    end
  end

  private

  def route_video_params
    params.require(:route_video).permit(:name, :file, settings: {})
  end

  # The recipe the studio rendered with. Only known keys are stored so a
  # crafted request cannot grow the row without bound.
  def settings_param
    (route_video_params[:settings] || {}).to_h.slice(
      'theme', 'format', 'duration_sec', 'camera_mode', 'follow_zoom',
      'track_color', 'track_width', 'hud_scale', 'units', 'watermark',
      'source', 'start_at', 'end_at'
    )
  end
end
