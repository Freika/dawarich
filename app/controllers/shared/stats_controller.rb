# frozen_string_literal: true

class Shared::StatsController < ApplicationController
  before_action :authenticate_user!, except: [:show]
  before_action :authenticate_active_user!, only: [:update]

  def show
    @stat = Stat.find_by(sharing_uuid: params[:uuid])

    unless @stat&.public_accessible?
      return redirect_to root_path,
                         alert: 'Shared stats not found or no longer available'
    end

    @year = @stat.year
    @month = @stat.month
    @user = @stat.user
    @is_public_view = true
    @data_bounds = @stat.calculate_data_bounds
    @hexagons_available = @stat.hexagons_available?

    render 'stats/public_month'
  end

  def update
    @year = params[:year].to_i
    @month = params[:month].to_i
    @stat = current_user.stats.find_by(year: @year, month: @month)

    return head :not_found unless @stat

    if params[:enabled] == '1'
      @stat.enable_sharing!(expiration: params[:expiration] || 'permanent')
      sharing_url = shared_stat_url(@stat.sharing_uuid)

      render json: {
        success: true,
        sharing_url: sharing_url,
        message: 'Sharing enabled successfully'
      }
    else
      @stat.disable_sharing!

      render json: {
        success: true,
        message: 'Sharing disabled successfully'
      }
    end
  rescue StandardError
    render json: {
      success: false,
      message: 'Failed to update sharing settings'
    }, status: :unprocessable_content
  end
end
