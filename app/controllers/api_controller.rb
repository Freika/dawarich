# frozen_string_literal: true

class ApiController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_key

  private

  def authenticate_api_key
    return head :unauthorized unless current_api_user

    true
  end

  def current_api_user
    @current_api_user ||= User.find_by(api_key: params[:api_key])
  end

  def validate_params
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      render json: {
        error: "Missing required parameters: #{missing_params.join(', ')}"
      }, status: :bad_request and return
    end

    params.permit(*required_params)
  end

  def required_params
    []
  end
end
