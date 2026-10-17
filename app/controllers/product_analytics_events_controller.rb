# frozen_string_literal: true

class ProductAnalyticsEventsController < ApplicationController
  before_action :authenticate_user!

  ONBOARDING_EVENTS = %w[onboarding_shown onboarding_choice_selected onboarding_completed].freeze

  def create
    return head :forbidden if DawarichSettings.self_hosted? || !current_user.product_analytics_consent?
    return record_web_first_observed if params[:event] == 'web_first_observed'
    return render_invalid_event unless valid_onboarding_event?

    properties = params[:event] == 'onboarding_choice_selected' ? { choice: params[:choice] } : {}
    ProductAnalytics.capture(user: current_user, event: params[:event], channel: 'web', platform: 'web',
                             properties: properties)
    head :accepted
  end

  private

  def record_web_first_observed
    current_user.with_lock do
      if current_user.product_analytics_web_observed_at.nil? &&
         ProductAnalytics.capture(user: current_user, event: 'web_first_observed', channel: 'web', platform: 'web')
        current_user.update!(product_analytics_web_observed_at: Time.current)
      end
    end
    head :accepted
  end

  def valid_onboarding_event?
    return false unless ONBOARDING_EVENTS.include?(params[:event])
    return true unless params[:event] == 'onboarding_choice_selected'

    ProductAnalytics::ENUMS.fetch('choice').include?(params[:choice])
  end

  def render_invalid_event
    render json: { error: 'invalid_event' }, status: :unprocessable_content
  end
end
