# frozen_string_literal: true

class ProductAnalyticsEventsController < ApplicationController
  before_action :authenticate_user!

  EVENTS = %w[web_first_observed].freeze

  def create
    return head :forbidden if DawarichSettings.self_hosted? || !current_user.product_analytics_consent?
    unless EVENTS.include?(params[:event])
      return render(json: { error: 'invalid_event' },
                    status: :unprocessable_content)
    end

    current_user.with_lock do
      if current_user.product_analytics_web_observed_at.nil? &&
         ProductAnalytics.capture(user: current_user, event: 'web_first_observed', channel: 'web', platform: 'web')
        current_user.update!(product_analytics_web_observed_at: Time.current)
      end
    end
    head :accepted
  end
end
