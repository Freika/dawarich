# frozen_string_literal: true

class Api::V1::Users::DestroyController < ApiController
  skip_before_action :reject_pending_payment!

  DELETION_MESSAGE = 'Your account has been scheduled for deletion. If you have an active Apple or ' \
                     'Google subscription, cancel it in your platform settings to avoid further charges.'

  def destroy
    Users::Destroy.new(current_api_user).call
    render json: { message: DELETION_MESSAGE }
  end
end
