# frozen_string_literal: true

class Api::V1::PointsController < ApplicationController
  before_action :authenticate_user!

  def destroy
    point = current_user.points.find(params[:id])
    point.destroy

    render json: { message: 'Point deleted successfully' }
  end
end
