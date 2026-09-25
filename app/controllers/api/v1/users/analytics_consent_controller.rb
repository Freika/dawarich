# frozen_string_literal: true

class Api::V1::Users::AnalyticsConsentController < ApiController
  skip_before_action :reject_pending_payment!, raise: false

  def show
    render_consent
  end

  def update
    return head :forbidden if DawarichSettings.self_hosted?

    consent = { true => true, false => false, 'true' => true, 'false' => false }[params[:consent]]
    return render(json: { error: 'invalid_consent' }, status: :unprocessable_content) if consent.nil?

    ProductAnalyticsConsent.update!(user: current_api_user, consent: consent)
    render_consent
  end

  private

  def render_consent
    render json: {
      consent: current_api_user.product_analytics_consent,
      analytics_id: current_api_user.product_analytics_consent? ? current_api_user.product_analytics_id : nil
    }
  end
end
