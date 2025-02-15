# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  before_action :authenticate_self_hosted!
  before_action :authenticate_admin!, unless: lambda {
    %w[start_immich_import start_photoprism_import].include?(params[:job_name])
  }

  def index
    @queues = Sidekiq::Queue.all
  end

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

  def destroy
    # Clear all jobs in the queue, params[:id] contains queue name
    queue = Sidekiq::Queue.new(params[:id])

    queue.clear

    flash.now[:notice] = 'Queue was successfully cleared.'
    redirect_to settings_background_jobs_path, notice: 'Queue was successfully cleared.'
  end
end
