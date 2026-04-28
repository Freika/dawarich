# frozen_string_literal: true

class Api::V1::Auth::GoogleController < Api::V1::Auth::BaseController
  PROVIDER = 'google'
  PROVIDER_LABEL = 'Google'

  def create
    claims =
      begin
        Auth::VerifyGoogleToken.new(params[:id_token], nonce: params[:nonce]).call
      rescue Auth::VerifyGoogleToken::InvalidToken => e
        return render_auth_error("Google token verification failed: #{e.message}")
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
      message: 'Google has not verified this email. Sign in with password and link from settings.'
    }, status: :forbidden
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
    render json: {
      error: 'verification_sent',
      message: 'This email already has a Dawarich account. ' \
               'We sent a confirmation link to that address — click it to link your Google sign-in.'
    }, status: :accepted
  end

  private

  # Google sends email_verified as a boolean (or string in some flows).
  def email_verified?(claims)
    [true, 'true'].include?(claims[:email_verified])
  end
end
