# frozen_string_literal: true

class Api::V1::Users::DestroyController < ApiController
  skip_before_action :reject_pending_payment!

  REQUEST_MESSAGE = 'A confirmation email has been sent. Click the link in the email to permanently ' \
                    'delete your account. If you have an active Apple or Google subscription, cancel ' \
                    'it in your platform settings to avoid further charges.'

  def destroy
    token = Users::IssueDestroyToken.new(current_api_user).call
    link_url = Rails.application.routes.url_helpers.user_destroy_confirmation_url(
      token: token,
      host: default_mailer_host,
      protocol: default_mailer_protocol
    )

    Users::MailerSendingJob.perform_later(
      current_api_user.id,
      'account_destroy_confirmation',
      link_url: link_url
    )

    render json: { message: REQUEST_MESSAGE }, status: :accepted
  end

  private

  def default_mailer_host
    ActionMailer::Base.default_url_options[:host] || ENV.fetch('APP_HOST', 'localhost')
  end

  def default_mailer_protocol
    ActionMailer::Base.default_url_options[:protocol] || 'https'
  end
end
