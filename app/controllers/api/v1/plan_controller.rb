# frozen_string_literal: true

class Api::V1::PlanController < ApiController
  def show
    features = if DawarichSettings.self_hosted? || current_api_user.pro?
                 full_features
               else
                 lite_features
               end

    render json: { plan: current_api_user.plan, features: features }
  end

  private

  def full_features
    { heatmap: true, fog_of_war: true, scratch_map: true,
      globe_view: true, integrations: true, write_api: true,
      sharing: true, full_digest: true, data_window: nil }
  end

  def lite_features
    { heatmap: false, fog_of_war: false, scratch_map: false,
      globe_view: false, integrations: false, write_api: :create_only,
      sharing: false, full_digest: false, data_window: '12_months' }
  end
end
