# frozen_string_literal: true

class Settings::BackgroundJobsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_first_user!

  def index
    @queues = Sidekiq::Queue.all
  end

  def show; end

  def new
  end

  def edit; end

  def create
  end

  def update
  end

  def destroy
  end
end
