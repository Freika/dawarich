# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!

  def index
    @stats = current_user.stats.group_by(&:year).sort.reverse
  end

  def show
    @year = params[:year].to_i
    @stats = current_user.stats.where(year: @year).order(:month)
  end

  def update
    StatCreatingJob.perform_later(current_user.id)

    redirect_to stats_path, notice: 'Stats are being updated', status: :see_other
  end
end
