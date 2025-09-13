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
end
