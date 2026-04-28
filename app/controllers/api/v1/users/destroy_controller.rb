# frozen_string_literal: true

class Api::V1::Users::DestroyController < ApiController
  skip_before_action :reject_pending_payment!

  SUBSCRIPTION_NOTE = ' If you have an active Apple or Google subscription, cancel it in your ' \
                      'platform settings to avoid further charges.'
  SELF_HOSTED_DELETED_MESSAGE = 'Your account has been scheduled for deletion.'

  def destroy
    DawarichSettings.self_hosted? ? destroy_self_hosted : destroy_cloud
  end

  private

  def destroy_self_hosted
    unless current_api_user.valid_password?(params[:password].to_s)
      return render(json: { error: 'password_required',
                            message: 'Provide your current password to delete your account.' },
                    status: :unauthorized)
    end

    Users::DestroyJob.perform_later(current_api_user.id) \
      if current_api_user.mark_as_deleted_atomically!

    render json: { message: SELF_HOSTED_DELETED_MESSAGE }
  end

  def destroy_cloud
    result = Users::RequestAccountDestroy.new(
      current_api_user,
      host: default_mailer_host,
      protocol: default_mailer_protocol
    ).call

    case result.status
    when :sent
      render json: { message: result.message + SUBSCRIPTION_NOTE }, status: :accepted
    when :throttled
      render json: { error: 'rate_limited', message: result.message }, status: :too_many_requests
    end
  end

  def default_mailer_host
    ActionMailer::Base.default_url_options[:host] || ENV.fetch('APP_HOST', 'localhost')
  end

  def default_mailer_protocol
    ActionMailer::Base.default_url_options[:protocol] || 'https'
  end
end
