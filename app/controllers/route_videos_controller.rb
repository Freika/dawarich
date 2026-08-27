# frozen_string_literal: true

# Receives videos the browser has already rendered. The MP4 arrives as an
# Active Storage signed id from a direct upload, so the request body stays
# small and the file never passes through a Rails process.
class RouteVideosController < ApplicationController
  include FlashStreamable

  # A direct upload puts the browser in charge of what the signed id names, so
  # the blob is checked before it is adopted rather than after.
  ALLOWED_CONTENT_TYPES = %w[video/mp4].freeze
  MAX_FILE_BYTES = 250.megabytes
  MAX_SETTING_LENGTH = 64

  before_action :authenticate_user!

  def create
    blob = ActiveStorage::Blob.find_signed!(route_video_params[:file])
    return reject_file(blob) unless storable?(blob)

    route_video = current_user.route_videos.new(
      name: route_video_params[:name].presence || I18n.t('controllers.route_videos.untitled'),
      status: :stored,
      settings: settings_param
    )
    route_video.file.attach(blob)
    route_video.save!
    evicted = RouteVideo.expire_over_cap(current_user.id)

    render turbo_stream: [
      turbo_stream.prepend('route-video-gallery-list', partial: 'route_videos/route_video',
                                                      locals: { route_video: route_video }),
      *evicted.map { |video| replace_card(video) },
      stream_flash(:notice, I18n.t('controllers.route_videos.saved'))
    ]
  rescue StandardError => e
    ExceptionReporter.call(e, 'Route video save failed')
    blob.purge_later if blob && !blob.attachments.exists?

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

  # A card the save just evicted is still on the page pointing at a file that
  # is about to 404.
  def replace_card(route_video)
    turbo_stream.replace(route_video, partial: 'route_videos/route_video',
                                      locals: { route_video: route_video })
  end

  def storable?(blob)
    ALLOWED_CONTENT_TYPES.include?(blob.content_type) && blob.byte_size <= MAX_FILE_BYTES
  end

  # The direct upload has already written the blob, and nothing sweeps
  # unattached ones — a refusal that just returns strands it forever.
  def reject_file(blob)
    blob.purge_later
    render turbo_stream: stream_flash(:error, I18n.t('controllers.route_videos.rejected_file')),
           status: :unprocessable_content
  end

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
    ).transform_values { |value| value.to_s.first(MAX_SETTING_LENGTH) }
  end
end
