# frozen_string_literal: true

class Api::V1::Auth::RegistrationsController < Api::V1::Auth::BaseController
  def create
    user = User.new(new_user_attrs)

    if user.save
      render_auth_success(user, status: :created)
    else
      render json: {
        error: 'validation_failed',
        details: user.errors.as_json
      }, status: :unprocessable_content
    end
  end

  private

  def new_user_attrs
    base = {
      email: params[:email],
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    }
    return base if DawarichSettings.self_hosted?

    # Cloud signups land in pending_payment until Manager emits the
    # subscription callback; skip_auto_trial suppresses the after_commit
    # trial start so we don't grant a trial to someone who hasn't paid.
    base.merge(status: :pending_payment, skip_auto_trial: true)
  end
end
