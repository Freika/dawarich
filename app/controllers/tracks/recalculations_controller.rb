# frozen_string_literal: true

class Tracks::RecalculationsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!

  def create
    status = Tracks::TransportationRecalculationStatus.new(current_user.id)

    if status.in_progress?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(
            :notice,
            I18n.t('controllers.tracks.recalculations.re_classification_already_running')
          )
        end
        format.html do
          redirect_back(fallback_location: root_path,
                        notice: I18n.t('controllers.tracks.recalculations.re_classification_already_running'))
        end
      end
    else
      Tracks::TransportationModeRecalculationJob.perform_later(current_user.id)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(
            :success,
            I18n.t('controllers.tracks.recalculations.re_classification_started_your_tracks_will_update_over_the_next')
          )
        end
        format.html do
          notice = I18n.t(
            'controllers.tracks.recalculations.re_classification_started_your_tracks_will_update_over_the_next'
          )
          redirect_back(
            fallback_location: root_path,
            notice: notice
          )
        end
      end
    end
  end
end
