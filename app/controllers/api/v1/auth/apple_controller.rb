# frozen_string_literal: true

class Api::V1::Auth::AppleController < Api::V1::Auth::BaseController
  PROVIDER = 'apple'
  PROVIDER_LABEL = 'Sign in with Apple'

  def create
    claims =
      begin
        Auth::VerifyAppleToken.new(params[:id_token], nonce: params[:nonce]).call
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
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    render json: {
      error: 'email_not_verified',
      message: 'Apple has not verified this email. Sign in with password and link from settings.'
    }, status: :forbidden
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
    render json: {
      error: 'verification_sent',
      message: 'This email already has a Dawarich account. ' \
               'We sent a confirmation link to that address — click it to link your Apple ID.'
    }, status: :accepted
  rescue Auth::FindOrCreateOauthUser::MissingOauthEmail => e
    Rails.logger.warn("apple.auth.missing_email uid=#{e.uid}")
    render json: {
      error: 'apple_email_missing',
      message: "We couldn't find your existing account, and Apple didn't share your email " \
               'with us this time. Apple only shares it once. Please go to ' \
               'appleid.apple.com → Sign in with Apple, find Dawarich, choose ' \
               '"Stop using Sign in with Apple", then try signing in again.'
    }, status: :unprocessable_entity
  end

  private

  # Apple sends email_verified as a string 'true'/'false' in id_tokens.
  def email_verified?(claims)
    [true, 'true'].include?(claims[:email_verified])
  end
end
