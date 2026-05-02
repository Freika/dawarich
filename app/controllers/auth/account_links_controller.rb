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

  def challenge
    pending = pending_oauth_link
    return redirect_to(new_user_session_path, alert: 'No pending account link.') unless pending

    user = User.find_by(id: pending['user_id'])
    return redirect_to(new_user_session_path, alert: 'Account no longer exists.') unless user

    @user_email = user.email
    @provider_label = pending['provider_label'].presence || provider_label(pending['provider'])
  end

  def confirm
    pending = pending_oauth_link
    return redirect_to(new_user_session_path, alert: 'No pending account link.') unless pending

    user = User.find_by(id: pending['user_id'])
    return redirect_to(new_user_session_path, alert: 'Account no longer exists.') unless user

    unless user.valid_password?(params[:password].to_s)
      flash.now[:alert] = 'Incorrect password.'
      @user_email = user.email
      @provider_label = pending['provider_label'].presence || provider_label(pending['provider'])
      return render :challenge, status: :unprocessable_entity
    end

    user.update!(provider: pending['provider'], uid: pending['uid'])
    session.delete(:pending_oauth_link)

    if user.otp_required_for_login?
      redirect_to new_user_session_path,
                  notice: "#{pending['provider_label']} is now linked to your account. " \
                          'Sign in with your password and 2FA code to continue.'
    else
      sign_in(user)
      redirect_to root_path,
                  notice: "#{pending['provider_label']} is now linked to your account."
    end
  end

  def email_fallback
    pending = pending_oauth_link
    return redirect_to(new_user_session_path, alert: 'No pending account link.') unless pending

    user = User.find_by(id: pending['user_id'])
    return redirect_to(new_user_session_path, alert: 'Account no longer exists.') unless user

    cache_key = "#{Auth::FindOrCreateOauthUser::LINK_EMAIL_RATE_LIMIT_KEY_PREFIX}#{user.id}"
    acquired = Rails.cache.write(cache_key, true,
                                 expires_in: Auth::FindOrCreateOauthUser::LINK_EMAIL_RATE_LIMIT_WINDOW,
                                 unless_exist: true)

    if acquired
      token = Auth::IssueAccountLinkToken.new(user, provider: pending['provider'], uid: pending['uid']).call
      link_url = auth_account_link_url(token: token)
      Users::MailerSendingJob.perform_later(
        user.id,
        'oauth_account_link',
        provider_label: pending['provider_label'],
        link_url: link_url
      )
    end

    redirect_to new_user_session_path,
                notice: "We sent a confirmation link to #{user.email}. " \
                        'Click it to link your account.'
  end

  private

  def pending_oauth_link
    pending = session[:pending_oauth_link]
    return nil unless pending.is_a?(Hash)
    return nil if pending['expires_at'].to_i < Time.current.to_i

    pending
  end

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end

  def provider_label(provider)
    {
      'apple' => 'Sign in with Apple',
      'google' => 'Google',
      'google_oauth2' => 'Google',
      'github' => 'GitHub',
      'openid_connect' => defined?(OIDC_PROVIDER_NAME) ? OIDC_PROVIDER_NAME : 'OpenID Connect'
    }.fetch(provider.to_s, provider.to_s.titleize)
  end
end
