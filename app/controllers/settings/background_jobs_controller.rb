# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def index
    @queues = Sidekiq::Queue.all
  end

  def create
    EnqueueReverseGeocodingJob.perform_later(params[:job_name], current_user.id)

    flash.now[:notice] = 'Job was successfully created.'

    redirect_to settings_background_jobs_path, notice: 'Job was successfully created.'
  end

  def destroy
    # Clear all jobs in the queue, params[:id] contains queue name
    queue = Sidekiq::Queue.new(params[:id])

    queue.clear

    flash.now[:notice] = 'Queue was successfully cleared.'
    redirect_to settings_background_jobs_path, notice: 'Queue was successfully cleared.'
  end
end
