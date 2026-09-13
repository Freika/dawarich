# frozen_string_literal: true

class Visits::RedetectionsController < ApplicationController
  before_action :authenticate_user!

  COOLDOWN = 1.hour

  def create
    if cooldown_active?
      respond_to do |format|
        format.html do
          redirect_to settings_visits_path,
                      alert: I18n.t('controllers.visits.redetections.re_detect_ran_recently_try_again_in_an_hour'),
                      status: :too_many_requests
        end
        format.json { render json: { error: 'cooldown_active' }, status: :too_many_requests }
      end
      return
    end

    Visits::FullHistoryRedetectJob.perform_later(current_user.id)
    redirect_to settings_visits_path,
                notice: I18n.t('controllers.visits.redetections.re_detection_queued_we_ll_notify_you_when_it_finishes')
  end

  private

  def cooldown_active?
    last = current_user.visits_redetected_at
    last.present? && last > COOLDOWN.ago
  end
end
