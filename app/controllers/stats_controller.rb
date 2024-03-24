class StatsController < ApplicationController
  before_action :authenticate_user!

  def index
    @stats = current_user.stats.group_by(&:year).sort_by { _1 }.reverse
  end

  def update
    StatCreatingJob.perform_later(current_user.id)

    redirect_to stats_path, notice: 'Stats are being updated', status: :see_other
  end
end
