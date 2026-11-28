# frozen_string_literal: true

class Shared::StatsController < ApplicationController
  include DefaultDateTimePreferences
  include FlashStreamable
  include SharingToggleable

  before_action :authenticate_user!, except: [:show]
  before_action :authenticate_active_user!, only: [:update]
  before_action :require_pro!, only: [:update]

  def show
    @stat = Stat.find_by(sharing_uuid: params[:uuid])

    unless @stat&.public_accessible? && @stat.user
      return redirect_to root_path,
                         alert: I18n.t('controllers.shared.stats.shared_stats_not_found_or_no_longer_available')
    end

    @year = @stat.year
    @month = @stat.month
    @user = @stat.user
    @is_public_view = true
    @data_bounds = @stat.calculate_data_bounds(privacy_zone_masker: Maps::PrivacyZoneMasker.new(@user))
    @hexagons_available = @stat.hexagons_available?

    render 'stats/public_month'
  end

  def update
    @year = params[:year].to_i
    @month = params[:month].to_i
    @stat = current_user.stats.find_by(year: @year, month: @month)

    return head :not_found unless @stat

    toggle_sharing(@stat, 'controllers.shared.stats') { |uuid| shared_stat_url(uuid) }
  end
end
