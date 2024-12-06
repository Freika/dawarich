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
    current_user.years_tracked.each do |year|
      (1..12).each do |month|
        Stats::CalculatingJob.perform_later(current_user.id, year, month)
      end
    end

    redirect_to stats_path, notice: 'Stats are being updated', status: :see_other
  end
end
