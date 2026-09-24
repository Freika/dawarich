# frozen_string_literal: true

class ProductAnalyticsConsentsController < ApplicationController
  before_action :authenticate_user!

  def update
    return head :forbidden if DawarichSettings.self_hosted?

    consent = { true => true, false => false, 'true' => true, 'false' => false }[params[:consent]]
    return render(json: { error: 'invalid_consent' }, status: :unprocessable_content) if consent.nil?

    ProductAnalyticsConsent.update!(user: current_user, consent: consent)
    render json: { consent: current_user.product_analytics_consent,
                   analytics_id: current_user.product_analytics_id }
  end
end
