# frozen_string_literal: true

class Api::V1::StatsController < ApplicationController
  skip_forgery_protection
  before_action :authenticate_api_key

  def index
    render json: StatsSerializer.new(current_api_user).call
  end
end
