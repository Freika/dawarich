# frozen_string_literal: true

module Trial
  class UpgradesController < ApplicationController
    before_action :authenticate_user!

    def show
      token = current_user.generate_subscription_token(
        plan: sanitized_plan,
        interval: sanitized_interval
      )
      Rails.logger.info(
        { event: 'trial_upgrades_viewed',
          user_id: current_user&.id,
          plan: sanitized_plan,
          interval: sanitized_interval }.to_json
      )
      redirect_to "#{MANAGER_URL}/auth/dawarich?token=#{token}", allow_other_host: true
    end

    private

    def sanitized_plan
      %w[pro lite].include?(params[:plan]) ? params[:plan] : nil
    end

    def sanitized_interval
      %w[annual monthly].include?(params[:interval]) ? params[:interval] : nil
    end
  end
end
