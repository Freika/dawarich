# frozen_string_literal: true

class Api::V1::PushSubscriptionsController < ApiController
  def update
    return head :service_unavailable unless PushSubscription.enabled_providers.include?(params[:provider])

    PushSubscription.transaction do
      token = params.require(:push_token)
      subscription = PushSubscription.find_by(push_token: token, provider: params[:provider],
                                              environment: params[:environment]) ||
                     PushSubscription.find_or_initialize_by(user: current_api_user, installation_id: params[:id])
      PushSubscription.where(user: current_api_user,
                             installation_id: params[:id]).where.not(id: subscription.id).delete_all
      subscription.update!(user: current_api_user, installation_id: params[:id], push_token: token,
                           context_id: params.require(:context_id), provider: params[:provider],
                           environment: params[:environment],
                           api_key_digest: Digest::SHA256.hexdigest(current_api_user.api_key.to_s),
                           expires_at: 30.days.from_now)
    end
    head :no_content
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    render json: { error: 'Invalid push subscription' }, status: :unprocessable_content
  end

  def destroy
    PushSubscription.where(user: current_api_user, installation_id: params[:id]).delete_all
    head :no_content
  end
end
