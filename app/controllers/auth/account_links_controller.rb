# frozen_string_literal: true

class Auth::AccountLinksController < ApplicationController
  include PendingImportClaimable

  MAX_FAILED_PASSWORD_ATTEMPTS = 5

  before_action :no_store_headers

  def show
    result =
      begin
        Auth::VerifyAccountLinkToken.new(params[:token]).call
      rescue Auth::VerifyAccountLinkToken::TokenReplayed
        return redirect_to(new_user_session_path,
                           alert: I18n.t('controllers.auth.account_links.this_link_has_already_been_used'))
      rescue Auth::VerifyAccountLinkToken::InvalidToken
        return redirect_to(new_user_session_path,
                           alert: I18n.t('controllers.auth.account_links.link_invalid_or_expired'))
      end

    user = result.user

    if user.provider.present? && (user.provider != result.provider || user.uid != result.uid)
      return redirect_to(new_user_session_path,
                         alert: I18n.t(
                           'controllers.auth.account_links.already_linked_to_different_identity',
                           provider: user.provider
                         ))
    end

    unless Auth::VerifyAccountLinkToken.consume!(result.jti)
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.this_link_has_already_been_used'))
    end

    user.update!(provider: result.provider, uid: result.uid)

    if user.otp_required_for_login?
      redirect_to(
        new_user_session_path,
        notice: I18n.t(
          'controllers.auth.account_links.linked_sign_in_with_two_factor',
          provider: provider_label(result.provider)
        )
      )
    else
      sign_in(user)
      claim_pending_import_for(user)
      redirect_to root_path,
                  notice: I18n.t('controllers.auth.account_links.provider_is_now_linked_to_your_account',
                                 provider: provider_label(result.provider))
    end
  end

  def challenge
    pending = pending_oauth_link
    unless pending
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.no_pending_account_link'))
    end

    user = User.find_by(id: pending['user_id'])
    unless user
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.account_no_longer_exists'))
    end

    @user_email = user.email
    @provider_label = label_for(pending)
  end

  def confirm
    pending = pending_oauth_link
    unless pending
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.no_pending_account_link'))
    end

    user = User.find_by(id: pending['user_id'])
    unless user
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.account_no_longer_exists'))
    end

    unless user.valid_password?(params[:password].to_s)
      session[:pending_oauth_link_attempts] = (session[:pending_oauth_link_attempts] || 0) + 1

      if session[:pending_oauth_link_attempts] >= MAX_FAILED_PASSWORD_ATTEMPTS
        clear_pending_oauth_link
        alert = I18n.t('controllers.auth.account_links.too_many_invalid_attempts_start_the_linking_flow_again')
        return redirect_to new_user_session_path,
                           alert: alert
      end

      flash.now[:alert] = I18n.t('controllers.auth.account_links.incorrect_password')
      @user_email = user.email
      @provider_label = label_for(pending)
      return render :challenge, status: :unprocessable_entity
    end

    user.update!(provider: pending['provider'], uid: pending['uid'])
    clear_pending_oauth_link

    if user.otp_required_for_login?
      redirect_to new_user_session_path,
                  notice: I18n.t(
                    'controllers.auth.account_links.linked_sign_in_with_two_factor',
                    provider: label_for(pending)
                  )
    else
      sign_in(user)
      claim_pending_import_for(user)
      redirect_to root_path,
                  notice: I18n.t('controllers.auth.account_links.pending_is_now_linked_to_your_account',
                                 pending: label_for(pending))
    end
  end

  def email_fallback
    pending = pending_oauth_link
    unless pending
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.no_pending_account_link'))
    end

    user = User.find_by(id: pending['user_id'])
    unless user
      return redirect_to(new_user_session_path,
                         alert: I18n.t('controllers.auth.account_links.account_no_longer_exists'))
    end

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
        provider_label: label_for(pending),
        link_url: link_url
      )
    end

    redirect_to new_user_session_path,
                notice: I18n.t('controllers.auth.account_links.confirmation_link_sent', email: user.email)
  end

  private

  def pending_oauth_link
    pending = session[:pending_oauth_link]
    return nil unless pending.is_a?(Hash)
    return nil if pending['expires_at'].to_i < Time.current.to_i

    pending
  end

  def clear_pending_oauth_link
    session.delete(:pending_oauth_link)
    session.delete(:pending_oauth_link_attempts)
  end

  def no_store_headers
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end

  def label_for(pending)
    pending['provider_label'].presence || provider_label(pending['provider'])
  end

  def provider_label(provider)
    {
      'apple' => I18n.t('oauth_providers.sign_in_with_apple'),
      'google' => I18n.t('oauth_providers.google'),
      'google_oauth2' => I18n.t('oauth_providers.google'),
      'github' => I18n.t('oauth_providers.github'),
      'openid_connect' => defined?(OIDC_PROVIDER_NAME) ? OIDC_PROVIDER_NAME : I18n.t('oauth_providers.openid_connect')
    }.fetch(provider.to_s, provider.to_s.titleize)
  end
end
