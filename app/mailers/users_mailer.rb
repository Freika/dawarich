# frozen_string_literal: true

class UsersMailer < ApplicationMailer
  def archival_approaching
    @user = params[:user]
    @upgrade_url = "#{MANAGER_URL}/auth/dawarich?token=#{@user.generate_subscription_token}" \
                   '&utm_source=email&utm_medium=email&utm_campaign=archival_approaching&utm_content=upgrade'

    mail(to: @user.email, subject: I18n.t('mailers.users.archival_approaching.subject'))
  end

  # Sent by Auth::FindOrCreateOauthUser when a mobile OAuth signup
  # collides with an existing email-password account. The recipient
  # clicks the signed link to confirm they own the email and merge
  # the OAuth identity onto the existing account.
  def oauth_account_link
    @user = params[:user]
    @provider_label = params[:provider_label]
    @link_url = params[:link_url]

    mail(
      to: @user.email,
      subject: I18n.t('mailers.users.oauth_account_link.subject', provider: @provider_label)
    )
  end

  def account_destroy_confirmation
    @user = params[:user]
    @link_url = params[:link_url]

    mail(to: @user.email, subject: I18n.t('mailers.users.account_destroy_confirmation.subject'))
  end

  def otp_account_locked
    @user = params[:user]

    mail(to: @user.email, subject: I18n.t('mailers.users.otp_account_locked.subject'))
  end

  def trial_expired; end

  def trial_expires_soon; end

  def post_trial_reminder_early; end

  def post_trial_reminder_late; end

  def welcome; end

  def explore_features; end
end
