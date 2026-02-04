# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  before_action :authenticate_self_hosted!
  before_action :authenticate_admin!, unless: lambda {
    action_name == 'create' &&
      %w[start_immich_import start_photoprism_import start_google_photos_import].include?(params[:job_name])
  }

  def index; end

  def update
    existing_settings = current_user.safe_settings.settings
    updated_settings = existing_settings.merge(settings_params)

    if current_user.update(settings: updated_settings)
      redirect_to settings_background_jobs_path, notice: 'Settings updated'
    else
      redirect_to settings_background_jobs_path, alert: 'Settings could not be updated'
    end
  end

  def create
    EnqueueBackgroundJob.perform_later(params[:job_name], current_user.id)

    flash.now[:notice] = 'Job was successfully created.'

    redirect_path =
      case params[:job_name]
      when 'start_immich_import', 'start_photoprism_import', 'start_google_photos_import'
        imports_path
      else
        settings_background_jobs_path
      end

    redirect_to redirect_path, notice: 'Job was successfully created.'
  end

  private

  def settings_params
    params.require(:settings).permit(:visits_suggestions_enabled)
  end
end
