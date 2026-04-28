# frozen_string_literal: true

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

    unless Auth::VerifyAccountLinkToken.consume!(result.jti)
      return redirect_to(new_user_session_path, alert: 'This link has already been used.')
    end

    user.update!(provider: result.provider, uid: result.uid)

    if user.otp_required_for_login?
      redirect_to(
        new_user_session_path,
        notice: "#{provider_label(result.provider)} is now linked to your account. " \
                'Sign in with your password and 2FA code to continue.'
      )
    else
      sign_in(user)
      redirect_to root_path, notice: "#{provider_label(result.provider)} is now linked to your account."
    end
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
