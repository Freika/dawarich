# frozen_string_literal: true

class Api::V1::Auth::RegistrationsController < Api::V1::Auth::BaseController
  def create
    user = User.new(
      email: params[:email],
      password: params[:password],
      password_confirmation: params[:password_confirmation],
      skip_auto_trial: !DawarichSettings.self_hosted?
    )

    if user.save
      user.update!(status: :pending_payment) unless DawarichSettings.self_hosted?
      render_auth_success(user, status: :created)
    else
      render json: {
        error: 'validation_failed',
        details: user.errors.as_json
      }, status: :unprocessable_content
    end
  end
end
