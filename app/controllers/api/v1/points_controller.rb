class Api::V1::PointsController < ApplicationController
  skip_forgery_protection

  def create
    Owntracks::PointCreatingJob.perform_later(point_params)

    render json: {}, status: :ok
  end

  def destroy
    @point = Point.find(params[:id])
    @point.destroy

    head :no_content
  end

  private

  def point_params
    params.permit(
      :lat, :lon, :bs, :batt, :p, :alt, :acc, :vac, :vel, :conn, :SSID, :BSSID, :m, :tid, :tst,
      :topic, :_type, :cog, :t, inrids: [], inregions: [], point: {}
    )
  end
end
