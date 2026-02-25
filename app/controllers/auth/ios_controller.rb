# frozen_string_literal: true

module Auth
  class IosController < ApplicationController
    def success
      # If token is provided, this is the final callback for ASWebAuthenticationSession
      if params[:token].present?
        # ASWebAuthenticationSession will capture this URL and extract the token
        render plain: 'Authentication successful! You can close this window.', status: :ok
      else
        # This should not happen with our current flow, but keeping for safety
        render json: {
          success: true,
          message: 'iOS authentication successful',
          redirect_url: root_url
        }, status: :ok
      end
    end
  end
end
