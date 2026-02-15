# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  DEBOUNCE_PERIOD = 1.minute
  DEBOUNCE_JOB_TYPES = %w[
    start_immich_import
    start_photoprism_import
    start_google_photos_import
  ].freeze

  before_action :authenticate_self_hosted!
  before_action :authenticate_admin!, unless: lambda {
    action_name == 'create' && DEBOUNCE_JOB_TYPES.include?(params[:job_name])
  }
  before_action :check_job_debounce, only: :create

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
    set_job_debounce
    EnqueueBackgroundJob.perform_later(params[:job_name], current_user.id)

    redirect_path =
      case params[:job_name]
      when *DEBOUNCE_JOB_TYPES
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

  def job_debounce_key
    "background_job_debounce_#{current_user.id}_#{params[:job_name]}"
  end

  def check_job_debounce
    return unless Rails.cache.exist?(job_debounce_key)

    redirect_path =
      case params[:job_name]
      when *DEBOUNCE_JOB_TYPES
        imports_path
      else
        settings_background_jobs_path
      end

    redirect_to redirect_path, alert: 'Please wait before starting another import job.'
  end

  def set_job_debounce
    Rails.cache.write(job_debounce_key, true, expires_in: DEBOUNCE_PERIOD)
  end
end
