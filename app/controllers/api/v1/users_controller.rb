# frozen_string_literal: true

class Api::V1::UsersController < ApiController
  def me
    render json: Api::UserSerializer.new(current_api_user).call
  end
end
