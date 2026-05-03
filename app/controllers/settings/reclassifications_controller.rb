# frozen_string_literal: true

class Settings::ReclassificationsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!

  def create
    status = Tracks::TransportationRecalculationStatus.new(current_user.id)

    if status.in_progress?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: stream_flash(:notice, 'Re-classification already running') }
        format.html { redirect_back(fallback_location: root_path, notice: 'Re-classification already running') }
      end
    else
      Tracks::TransportationModeRecalculationJob.perform_later(current_user.id)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(
            :success,
            'Re-classification started — your tracks will update over the next few minutes'
          )
        end
        format.html do
          redirect_back(
            fallback_location: root_path,
            notice: 'Re-classification started — your tracks will update over the next few minutes'
          )
        end
      end
    end
  end
end
