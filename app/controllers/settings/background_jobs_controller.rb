# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_self_hosted!, unless: lambda {
    action_name == 'create' &&
      %w[start_immich_import start_photoprism_import start_airtrail_import].include?(params[:job_name])
  }

  def index; end

  def update
    existing_settings = current_user.safe_settings.settings
    updated_settings = existing_settings.merge(settings_params)

    if current_user.update(settings: updated_settings)
      redirect_to settings_background_jobs_path, notice: I18n.t('controllers.settings.background_jobs.settings_updated')
    else
      redirect_to settings_background_jobs_path,
                  alert: I18n.t('controllers.settings.background_jobs.settings_could_not_be_updated')
    end
  end

  def create
    EnqueueBackgroundJob.perform_later(params[:job_name], current_user.id)

    flash.now[:notice] = I18n.t('controllers.settings.background_jobs.job_was_successfully_created')

    redirect_path =
      case params[:job_name]
      when 'start_immich_import', 'start_photoprism_import'
        imports_path
      when 'start_airtrail_import'
        settings_integrations_path
      else
        settings_background_jobs_path
      end

    redirect_to redirect_path, notice: I18n.t('controllers.settings.background_jobs.job_was_successfully_created')
  end

  private

  def settings_params
    params.require(:settings).permit(:visits_suggestions_enabled)
  end
end
