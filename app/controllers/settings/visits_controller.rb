# frozen_string_literal: true

class Settings::VisitsController < ApplicationController
  before_action :authenticate_user!

  def show; end

  def update
    merged = (current_user.settings || {}).merge(coerced_settings_params)
    current_user.update!(settings: merged)

    redirect_to settings_visits_path, notice: I18n.t('controllers.settings.visits.visit_detection_settings_updated')
  end

  private

  def settings_params
    params.require(:settings).permit(:visit_radius_meters, :visit_min_points,
                                     :visit_min_duration_minutes)
  end

  def coerced_settings_params
    raw = settings_params.to_h
    coerced = {}
    coerced['visit_radius_meters'] = raw['visit_radius_meters'].to_i if raw.key?('visit_radius_meters')
    coerced['visit_min_points']    = raw['visit_min_points'].to_i    if raw.key?('visit_min_points')
    if raw.key?('visit_min_duration_minutes')
      coerced['visit_min_duration_minutes'] = raw['visit_min_duration_minutes'].to_i
    end
    coerced
  end
end
