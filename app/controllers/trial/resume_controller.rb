# frozen_string_literal: true

class Trial::ResumeController < ApplicationController
  before_action :authenticate_user!
  before_action :require_pending_payment

  def show
    @checkout_url = "#{MANAGER_URL}/checkout?token=#{current_user.generate_subscription_token(variant: 'reverse_trial')}"
  end

  private

  def require_pending_payment
    return if current_user.pending_payment?

    redirect_to root_path
  end
end
