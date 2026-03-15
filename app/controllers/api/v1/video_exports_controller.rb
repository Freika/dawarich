# frozen_string_literal: true

class Api::V1::VideoExportsController < ApiController
  include ActiveStorage::SetCurrent

  wrap_parameters false
  skip_before_action :authenticate_api_key, only: [:callback]

  before_action :require_video_service, except: [:callback]
  before_action :set_video_export, only: %i[show destroy]

  def index
    video_exports = current_api_user.video_exports.with_attached_file.order(created_at: :desc)

    if params[:page].present?
      per_page = (params[:per_page].presence&.to_i || 25).clamp(1, 100)
      video_exports = video_exports.page(params[:page]).per(per_page)

      response.set_header('X-Current-Page', video_exports.current_page.to_s)
      response.set_header('X-Total-Pages', video_exports.total_pages.to_s)
      response.set_header('X-Total-Count', video_exports.total_count.to_s)
    end

    render json: video_exports.map { |ve| serialize(ve) }
  end

  def show
    render json: serialize(@video_export)
  end

  def create
    video_export = current_api_user.video_exports.new(video_export_params)

    if video_export.save
      render json: serialize(video_export), status: :created
    else
      render json: { errors: video_export.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @video_export.destroy
    head :no_content
  end

  def callback
    if callback_rate_limited?(request.remote_ip)
      return render json: { error: 'Too many requests' }, status: :too_many_requests
    end

    video_export = VideoExport.includes(:user).find_by(id: params[:id])

    return render json: { error: 'Unauthorized' }, status: :unauthorized unless video_export

    token = params[:token]

    unless VideoExports::CallbackToken.verify(token, video_export.id, video_export.callback_nonce)
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    video_export.with_lock do
      if video_export.completed? || video_export.failed?
        return render json: { status: 'already_processed' }, status: :conflict
      end

      if params[:status] == 'completed' && params[:file].present?
        file = params[:file]
        detected_type = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
        unless detected_type.start_with?('video/')
          return render json: { error: 'Invalid file type' }, status: :unprocessable_content
        end
        return render json: { error: 'File too large' }, status: :unprocessable_content if file.size > 500.megabytes
        return render json: { error: 'File is empty' }, status: :unprocessable_content if file.size.zero? # rubocop:disable Style/ZeroLengthPredicate

        video_export.file.attach(file)
        video_export.update!(status: :completed)
        notify_user(video_export, :info, 'Video export ready', 'Your video export is ready for download.')
      else
        error_msg = params[:error_message].to_s.truncate(500)
        video_export.update!(status: :failed, error_message: error_msg)
        notify_user(video_export, :error, 'Video export failed',
                    "Video export failed: #{error_msg}")
      end
    end

    render json: { status: 'ok' }
  end

  private

  def set_video_export
    @video_export = current_api_user.video_exports.find(params[:id])
  end

  def video_export_params
    permitted = params.permit(:track_id, :start_at, :end_at)
    if params[:config].present?
      permitted[:config] = params[:config].permit(
        :orientation, :overlay_layout, :map_style, :target_duration,
        :map_behavior, :fit_full_route, :route_color, :route_width,
        :marker_style, :marker_color, :track_name, :screen_preset,
        overlays: %i[time speed distance track_name]
      ).to_h
    end
    permitted
  end

  def serialize(video_export)
    {
      id: video_export.id,
      name: video_export.display_name,
      track_id: video_export.track_id,
      status: video_export.status,
      config: video_export.config,
      start_at: video_export.start_at&.iso8601,
      end_at: video_export.end_at&.iso8601,
      error_message: video_export.error_message,
      created_at: video_export.created_at.iso8601,
      download_url: video_export.file.attached? ? url_for(video_export.file) : nil
    }
  end

  def notify_user(video_export, kind, title, content)
    Notifications::Create.new(user: video_export.user, kind:, title:, content:).call
  end

  def callback_rate_limited?(ip)
    key = "video_export_callback:#{ip}"
    count = Rails.cache.increment(key, 1, expires_in: 1.minute, initial: 0)
    count > 30
  end

  def require_video_service
    return if DawarichSettings.video_service_enabled?

    render json: { error: 'Video service is not available' }, status: :not_found
  end
end
