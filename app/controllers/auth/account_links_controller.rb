# frozen_string_literal: true

# Handles the click-through from the OAuth account-link verification email.
# A user who tries to sign in with Apple or Google on an email that already
# belongs to a password account receives a signed link by email; clicking
# the link here performs the merge (writes `provider` + `uid` onto the
# existing user) and signs them in.
class Auth::AccountLinksController < ApplicationController
  before_action :no_store_headers

  def show
    result =
      begin
        Auth::VerifyAccountLinkToken.new(params[:token]).call
      rescue Auth::VerifyAccountLinkToken::TokenReplayed
        return redirect_to(new_user_session_path, alert: 'This link has already been used.')
      rescue Auth::VerifyAccountLinkToken::InvalidToken
        return redirect_to(new_user_session_path, alert: 'Link invalid or expired.')
      end

    user = result.user

    if user.provider.present? && (user.provider != result.provider || user.uid != result.uid)
      return redirect_to(new_user_session_path,
                         alert: "This account is already linked to a different #{user.provider} identity.")
    end

    user.update!(provider: result.provider, uid: result.uid)
    Auth::VerifyAccountLinkToken.mark_consumed!(result.jti)
    sign_in(user)

    redirect_to root_path, notice: "#{provider_label(result.provider)} is now linked to your account."
  end

  private

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end

  def provider_label(provider)
    { 'apple' => 'Sign in with Apple', 'google' => 'Google' }.fetch(provider, provider.to_s.titleize)
  end
end
