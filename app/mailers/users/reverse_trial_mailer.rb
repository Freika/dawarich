# frozen_string_literal: true

module Users
  class ReverseTrialMailer < ApplicationMailer
    before_action :extract_user

    def trial_first_payment_soon
      mail(to: @user.email, subject: 'Your Dawarich first payment is coming up')
    end

    def trial_converted
      mail(to: @user.email, subject: 'Welcome to Dawarich Pro')
    end

    def pending_payment_day_1
      mail(to: @user.email, subject: 'Finish setting up your Dawarich account')
    end

    def pending_payment_day_3
      mail(to: @user.email, subject: 'Still want to try Dawarich?')
    end

    def pending_payment_day_7
      mail(to: @user.email, subject: "We're holding your Dawarich account")
    end

    private

    def extract_user
      @user = params[:user]
    end
  end
end
