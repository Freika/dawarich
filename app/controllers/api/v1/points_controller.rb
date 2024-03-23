class Api::V1::PointsController < ApplicationController
  skip_forgery_protection

  def create
    parsed_params = OwnTracks::Params.new(point_params).call

    @point = Point.create(parsed_params)

    if @point.valid?
      render json: @point, status: :ok
    else
      render json: @point.errors, status: :unprocessable_entity
    end
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
