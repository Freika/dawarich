# frozen_string_literal: true

class Api::V1::VideoExportsController < ApiController
  include ActiveStorage::SetCurrent

  wrap_parameters false
  skip_before_action :authenticate_api_key, only: [:callback]

  before_action :require_video_service, except: [:callback]
  before_action :set_video_export, only: %i[show destroy]

  def index
    video_exports = current_api_user.video_exports.order(created_at: :desc)

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
    video_export = VideoExport.find(params[:id])
    token = params[:token]

    unless VideoExports::CallbackToken.verify(token, video_export.id)
      return render json: { error: 'Invalid token' }, status: :unauthorized
    end

    if params[:status] == 'completed' && params[:file].present?
      video_export.file.attach(params[:file])
      video_export.update!(status: :completed)
      notify_user(video_export, :info, 'Video export ready', 'Your video export is ready for download.')
    else
      video_export.update!(status: :failed, error_message: params[:error_message])
      notify_user(video_export, :error, 'Video export failed',
                  "Video export failed: #{params[:error_message]}")
    end

    render json: { status: 'ok' }
  end

  private

  def set_video_export
    @video_export = current_api_user.video_exports.find(params[:id])
  end

  def video_export_params
    permitted = params.permit(:track_id, :start_at, :end_at)
    permitted[:config] = params[:config].permit!.to_h if params[:config].present?
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
    video_export.user.notifications.create!(
      title: title,
      content: content,
      kind: kind
    )
  end

  def require_video_service
    return if DawarichSettings.video_service_enabled?

    render json: { error: 'Video service is not available' }, status: :not_found
  end
end
