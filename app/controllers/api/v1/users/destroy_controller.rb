# frozen_string_literal: true

class Api::V1::Users::DestroyController < ApiController
  include AccountDeletionConfirmable

  skip_before_action :reject_pending_payment!

  def destroy
    unless current_api_user.can_delete_account?
      message = I18n.t('controllers.api.v1.users.destroy.cannot_delete')
      return render(json: { error: 'cannot_delete_account', message: message },
                    status: :unprocessable_content)
    end

    DawarichSettings.self_hosted? ? destroy_self_hosted : destroy_cloud
  end

  private

  def destroy_self_hosted
    unless account_deletion_confirmed?(current_api_user)
      log_failed_account_deletion(current_api_user)

      return render(json: { error: 'password_required',
                            message: account_deletion_confirmation_error(current_api_user) },
                    status: :unauthorized)
    end

    Users::DestroyJob.perform_later(current_api_user.id) \
      if current_api_user.mark_as_deleted_atomically!

    render json: { message: I18n.t('controllers.api.v1.users.destroy.deletion_scheduled') }
  end

  def destroy_cloud
    result = Users::RequestAccountDestroy.new(
      current_api_user,
      host: default_mailer_host,
      protocol: default_mailer_protocol
    ).call

    case result.status
    when :sent
      render json: {
        message: I18n.t('controllers.api.v1.users.destroy.request_sent', message: result.message)
      }, status: :accepted
    when :throttled
      render json: { error: 'rate_limited', message: result.message }, status: :too_many_requests
    else
      raise "unexpected destroy result: #{result.status}"
    end
  end

  def default_mailer_host
    ActionMailer::Base.default_url_options[:host] || ENV.fetch('APP_HOST', 'localhost')
  end

  def default_mailer_protocol
    ActionMailer::Base.default_url_options[:protocol] || 'https'
  end
end
