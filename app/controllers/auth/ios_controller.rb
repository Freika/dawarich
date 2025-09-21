# frozen_string_literal: true

module Auth
  class IosController < ApplicationController
    def success
      render json: {
        success: true,
        message: 'iOS authentication successful',
        token: params[:token],
        redirect_url: root_url
      }, status: :ok
    end
  end
end