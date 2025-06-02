# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  before_action :authenticate_self_hosted!
  before_action :authenticate_admin!, unless: lambda {
    %w[start_immich_import start_photoprism_import].include?(params[:job_name])
  }

  def index;end

  def create
    EnqueueBackgroundJob.perform_later(params[:job_name], current_user.id)

    flash.now[:notice] = 'Job was successfully created.'

    redirect_path =
      case params[:job_name]
      when 'start_immich_import', 'start_photoprism_import'
        imports_path
      else
        settings_background_jobs_path
      end

    redirect_to redirect_path, notice: 'Job was successfully created.'
  end
end
