# frozen_string_literal: true

class Tracks::SegmentsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :load_track

  def index
    @segments = @track.track_segments.order(:start_at, :start_index)
    render layout: false
  end

  def update
    segment = @track.track_segments.find(params[:id])
    authorize segment, :update?

    result = if params[:reset] == 'true'
               Tracks::SegmentEditor.new(segment, current_user).reset_to_auto
             else
               Tracks::SegmentEditor.new(segment, current_user).apply_override(
                 segment_params[:transportation_mode]
               )
             end

    if result.success?
      track = result.track.reload
      dominant_label = I18n.t("transportation_modes.#{track.dominant_mode || 'unknown'}")

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            *segment_content_streams(result, track),
            turbo_stream.update("track-info-mode-#{track.id}", dominant_label),
            stream_flash(:success, I18n.t('controllers.tracks.segments.segment_updated'))
          ]
        end
        format.html do
          redirect_back(fallback_location: root_path, notice: I18n.t('controllers.tracks.segments.segment_updated'))
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, error_message_for(result.error_code)),
                 status: :unprocessable_entity
        end
        format.html do
          redirect_back(fallback_location: root_path, alert: error_message_for(result.error_code))
        end
      end
    end
  end

  private

  # A mode override keeps the row and additionally refreshes the simplified
  # legs block above the raw list (kept separate so the open <details> state
  # survives); a reset re-runs detection and replaces the whole list (the
  # original row no longer exists after reprocessing).
  def segment_content_streams(result, track)
    segments = track.track_segments.order(:start_at, :start_index)

    unless result.segment
      return [turbo_stream.replace(
        "track-#{track.id}-segments",
        partial: 'tracks/segments/list',
        locals: { track: track, segments: segments }
      )]
    end

    streams = [turbo_stream.replace(
      "segment-row-#{result.segment.id}",
      partial: 'tracks/segments/segment_row',
      locals: { segment: result.segment }
    )]

    display = TrackSegments::DisplayLegs.call(segments)
    if display
      streams << turbo_stream.replace(
        "track-#{track.id}-legs",
        partial: 'tracks/segments/legs',
        locals: { track: track, display: display }
      )
    end

    streams
  end

  def load_track
    @track = current_user.tracks.find(params[:track_id])
  end

  def segment_params
    params.require(:track_segment).permit(:transportation_mode)
  end

  def error_message_for(code)
    case code
    when :mode_not_enabled then I18n.t('controllers.tracks.segments.mode_not_enabled')
    when :reprocess_failed then I18n.t('controllers.tracks.segments.reprocess_failed')
    else I18n.t('controllers.tracks.segments.update_failed')
    end
  end
end
