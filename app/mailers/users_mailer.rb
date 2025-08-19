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
end
