# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update update_all]
  before_action :validate_update_period!, only: :update

  def index
    redirect_to insights_path(year: 'all')
  end

  def show
    redirect_to insights_path(year: params[:year].to_i)
  end

  def month
    @year = params[:year].to_i
    @month = params[:month].to_i
    @stat = current_user.scoped_stats.find_by(year: @year, month: @month)
    @previous_stat = current_user.scoped_stats.find_by(year: @year, month: @month - 1) if @month > 1
    @average_distance_this_year = current_user.scoped_stats.where(year: @year).average(:distance).to_i / 1000
    @sharing_allowed = current_user.full_access?
  end

  def update
    if params[:month] == 'all'
      (1..12).each do |month|
        Stats::CalculatingJob.perform_later(current_user.id, params[:year], month)
      end

      target = I18n.t('controllers.stats.whole_year', year: params[:year])
    else
      Stats::CalculatingJob.perform_later(current_user.id, params[:year], params[:month])

      month = I18n.l(Date.new(params[:year].to_i, params[:month].to_i, 1), format: :month_name)
      target = I18n.t('controllers.stats.month_of_year', month:, year: params[:year])
    end

    redirect_to insights_path(year: params[:year]),
                notice: I18n.t('controllers.stats.stats_for_target_are_being_updated', target: target),
                status: :see_other
  end

  def update_all
    Stats::EnqueueFullRecalculation.new(current_user).call

    redirect_to insights_path(year: 'all'), notice: I18n.t('controllers.stats.stats_are_being_updated'),
                                            status: :see_other
  end

  private

  def validate_update_period!
    return if params[:month] == 'all' || params[:month].to_s.match?(/\A(?:0?[1-9]|1[0-2])\z/)

    redirect_to insights_path,
                alert: I18n.t('controllers.stats.invalid_period'),
                status: :see_other
  end
end
