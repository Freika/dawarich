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

  def archival_approaching
    @user = params[:user]
    @upgrade_url = "#{MANAGER_URL}/auth/dawarich?token=#{@user.generate_subscription_token}" \
                   '&utm_source=email&utm_medium=email&utm_campaign=archival_approaching&utm_content=upgrade'

    mail(to: @user.email, subject: 'Keep your full history — upgrade to Pro')
  end
end
