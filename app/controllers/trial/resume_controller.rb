# frozen_string_literal: true

class Trial::ResumeController < ApplicationController
  before_action :no_store_headers
  before_action :authenticate_user!
  before_action :require_pending_payment

  def show
    token = current_user.generate_subscription_token(variant: 'reverse_trial')
    @checkout_url = "#{MANAGER_URL}/checkout?token=#{token}"
  end

  private

  def no_store_headers
    # The rendered page embeds a short-lived JWT in a checkout URL.
    # Disallow shared-cache / proxy caching so the token isn't leaked.
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end

  def require_pending_payment
    return if current_user.pending_payment?

    redirect_to root_path
  end
end
