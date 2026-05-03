# frozen_string_literal: true

class Tracks::SegmentsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :load_track

  def index
    @segments = @track.track_segments.order(:start_index)
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
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "segment-row-#{segment.id}",
              partial: 'tracks/segments/segment_row',
              locals: { segment: result.segment }
            ),
            stream_flash(:notice, 'Segment updated')
          ]
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, error_message_for(result.error_code)),
                 status: :unprocessable_entity
        end
      end
    end
  end

  private

  def load_track
    @track = current_user.tracks.find(params[:track_id])
  end

  def segment_params
    params.require(:track_segment).permit(:transportation_mode)
  end

  def error_message_for(code)
    case code
    when :mode_not_enabled then "That mode isn't enabled in your settings"
    else 'Could not update segment'
    end
  end
end
