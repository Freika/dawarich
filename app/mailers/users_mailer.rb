# frozen_string_literal: true

class UsersMailer < ApplicationMailer
  def welcome
    @user = params[:user]

    mail(to: @user.email, subject: 'Welcome to Dawarich!')
  end

  def explore_features
    @user = params[:user]

    mail(to: @user.email, subject: 'Explore Dawarich features!')
  end

  def trial_expires_soon
    @user = params[:user]

    mail(to: @user.email, subject: '⚠️ Your Dawarich trial expires in 2 days')
  end

  def trial_expired
    @user = params[:user]

    mail(to: @user.email, subject: '💔 Your Dawarich trial expired')
  end

  def post_trial_reminder_early
    @user = params[:user]

    mail(to: @user.email, subject: '🚀 Still interested in Dawarich? Subscribe now!')
  end

  def post_trial_reminder_late
    @user = params[:user]

    mail(to: @user.email, subject: '📍 Your location data is waiting - Subscribe to Dawarich')
  end

  def subscription_expires_soon_early
    @user = params[:user]

    mail(to: @user.email, subject: '⚠️ Your Dawarich subscription expires in 14 days')
  end

  def subscription_expires_soon_late
    @user = params[:user]

    mail(to: @user.email, subject: '🚨 Your Dawarich subscription expires in 2 days')
  end

  def subscription_expired_early
    @user = params[:user]

    mail(to: @user.email, subject: '💔 Your Dawarich subscription expired - Reactivate now')
  end

  def subscription_expired_late
    @user = params[:user]

    mail(to: @user.email, subject: '📍 Missing your location insights? Renew Dawarich subscription')
  end
end
