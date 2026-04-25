# frozen_string_literal: true

class Api::V1::Auth::AppleController < Api::V1::Auth::BaseController
  class UnverifiedEmail < StandardError; end
  class LinkVerificationSent < StandardError; end

  PROVIDER = 'apple'
  PROVIDER_LABEL = 'Sign in with Apple'

  def create
    claims =
      begin
        Auth::VerifyAppleToken.new(params[:id_token]).call
      rescue Auth::VerifyAppleToken::InvalidToken => e
        return render_auth_error("Apple token verification failed: #{e.message}")
      end

    user, created = Auth::FindOrCreateOauthUser.new(
      provider: PROVIDER,
      provider_label: PROVIDER_LABEL,
      claims: claims,
      email_verified: email_verified?(claims)
    ).call

    render_auth_success(user, status: created ? :created : :ok)
  rescue UnverifiedEmail
    render json: {
      error: 'email_not_verified',
      message: 'Apple has not verified this email. Sign in with password and link from settings.'
    }, status: :forbidden
  rescue LinkVerificationSent
    render json: {
      error: 'verification_sent',
      message: 'This email already has a Dawarich account. ' \
               'We sent a confirmation link to that address — click it to link your Apple ID.'
    }, status: :accepted
  end

  private

  # Apple sends email_verified as a string 'true'/'false' in id_tokens.
  def email_verified?(claims)
    [true, 'true'].include?(claims[:email_verified])
  end
end
