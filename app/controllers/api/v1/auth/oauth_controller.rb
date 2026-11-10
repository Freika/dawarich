# frozen_string_literal: true

# Native sign-in with a provider's ID token. Subclasses name the provider and
# supply its token verifier; message keys live under the provider's locale scope.
class Api::V1::Auth::OauthController < Api::V1::Auth::BaseController
  def create
    claims =
      begin
        token_verifier.new(params[:id_token], nonce: params[:nonce]).call
      rescue token_verifier::InvalidToken => e
        return render_auth_error(oauth_message(:token_verification_failed, message: e.message))
      end

    user, created = Auth::FindOrCreateOauthUser.new(
      provider: self.class::PROVIDER,
      provider_label: provider_label,
      claims: claims,
      email_verified: [true, 'true'].include?(claims[:email_verified])
    ).call

    render_auth_success(user, status: created ? :created : :ok)
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    render json: { error: 'email_not_verified', message: unverified_email_message }, status: :forbidden
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent => e
    if e.rate_limited
      response.headers['Retry-After'] = e.retry_after.to_s
      render json: {
        error: 'verification_rate_limited',
        message: oauth_message(:verification_rate_limited)
      }, status: :too_many_requests
    else
      render json: {
        error: 'verification_sent',
        message: oauth_message(:this_email_already_has_a_dawarich_account_we_sent_a)
      }, status: :accepted
    end
  rescue Auth::FindOrCreateOauthUser::AccountPendingDeletion
    render json: {
      error: 'account_pending_deletion',
      message: I18n.t('controllers.api.v1.auth.account_pending_deletion')
    }, status: :conflict
  end

  private

  def unverified_email_message
    oauth_message("#{self.class::LOCALE_SCOPE}_has_not_verified_this_email_sign_in_with_password")
  end

  def oauth_message(key, **options)
    I18n.t("controllers.api.v1.auth.#{self.class::LOCALE_SCOPE}.#{key}", **options)
  end
end
