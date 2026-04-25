# frozen_string_literal: true

class UsersMailer < ApplicationMailer
  def welcome
    # Sent after user signs up
    @user = params[:user]

    mail(to: @user.email, subject: 'Welcome to Dawarich!')
  end

  def explore_features
    # Sent 2 days after user signs up
    @user = params[:user]

    mail(to: @user.email, subject: 'Explore Dawarich features!')
  end

  def trial_expires_soon
    # Sent 2 days before trial expires
    @user = params[:user]

    mail(to: @user.email, subject: '⚠️ Your Dawarich trial expires in 2 days')
  end

  def trial_expired
    # Sent when trial expires
    @user = params[:user]

    mail(to: @user.email, subject: '💔 Your Dawarich trial expired')
  end

  def post_trial_reminder_early
    # Sent 2 days after trial expires
    @user = params[:user]

    mail(to: @user.email, subject: '🚀 Still interested in Dawarich? Subscribe now!')
  end

  def post_trial_reminder_late
    # Sent 7 days after trial expires
    @user = params[:user]

    mail(to: @user.email, subject: '📍 Your location data is waiting - Subscribe to Dawarich')
  end

  def archival_approaching
    @user = params[:user]
    @upgrade_url = "#{MANAGER_URL}/auth/dawarich?token=#{@user.generate_subscription_token}" \
                   '&utm_source=email&utm_medium=email&utm_campaign=archival_approaching&utm_content=upgrade'

    mail(to: @user.email, subject: 'Keep your full history — upgrade to Pro')
  end

  # Sent by Auth::FindOrCreateOauthUser when a mobile OAuth signup
  # collides with an existing email-password account. The recipient
  # clicks the signed link to confirm they own the email and merge
  # the OAuth identity onto the existing account.
  def oauth_account_link
    @user = params[:user]
    @provider_label = params[:provider_label]
    @link_url = params[:link_url]

    mail(to: @user.email, subject: "Confirm linking #{@provider_label} to your Dawarich account")
  end
end
