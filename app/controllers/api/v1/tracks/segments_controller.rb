# frozen_string_literal: true

# Reads and corrects a track's transportation-mode segments. The API twin of
# Tracks::SegmentsController: same Tracks::SegmentEditor, JSON instead of
# Turbo Streams.
class Api::V1::Tracks::SegmentsController < ApiController
  before_action :require_write_api!, only: :update
  before_action :load_track

  def index
    render json: track_payload(@track)
  end

  def update
    segment = @track.track_segments.find(params[:id])
    editor = Tracks::SegmentEditor.new(segment, current_api_user)

    result =
      if reset?
        editor.reset_to_auto
      elsif params[:transportation_mode].present?
        editor.apply_override(params[:transportation_mode].to_s)
      else
        return render_missing_parameter
      end

    return render_failure(result.error_code) unless result.success?

    track = result.track.reload
    segment_json = result.segment && Api::TrackSegmentSerializer.new(result.segment.reload).call
    render json: track_payload(track).merge(segment: segment_json)
  end

  private

  def load_track
    @track = current_api_user.tracks.find(params[:track_id])
  end

  def reset?
    ActiveModel::Type::Boolean.new.cast(params[:reset]) == true
  end

  def track_payload(track)
    {
      track_id: track.id,
      dominant_mode: track.dominant_mode,
      enabled_modes: enabled_modes,
      segments: track.track_segments.order(:start_at, :start_index).map do |segment|
        Api::TrackSegmentSerializer.new(segment).call
      end
    }
  end

  def enabled_modes
    current_api_user.safe_settings.enabled_transportation_modes
  end

  def render_missing_parameter
    render json: {
      error: 'missing_parameter',
      message: 'Provide either transportation_mode or reset: true'
    }, status: :bad_request
  end

  def render_failure(code)
    body = { error: code.to_s, message: error_message_for(code) }
    body[:enabled_modes] = enabled_modes if code == :mode_not_enabled

    render json: body, status: :unprocessable_content
  end

  def error_message_for(code)
    case code
    when :mode_not_enabled then I18n.t('controllers.tracks.segments.mode_not_enabled')
    when :reprocess_failed then I18n.t('controllers.tracks.segments.reprocess_failed')
    else I18n.t('controllers.tracks.segments.update_failed')
    end
  end
end
