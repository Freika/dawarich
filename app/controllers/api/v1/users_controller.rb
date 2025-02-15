# frozen_string_literal: true

class Api::V1::UsersController < ApiController
  def me
    render json: { user: current_api_user }
  end
end
