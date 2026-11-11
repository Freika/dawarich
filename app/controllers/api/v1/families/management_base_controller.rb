# frozen_string_literal: true

# Management has different lifecycle gates from location sharing: invitations
# can be accepted before membership, and cleanup must survive an expired plan.
class Api::V1::Families::ManagementBaseController < ApiController
  rescue_from Pundit::NotAuthorizedError do
    render json: { error: 'forbidden' }, status: :forbidden
  end
  rescue_from ActionController::ParameterMissing do |error|
    render json: { error: 'parameter_missing', message: error.message }, status: :bad_request
  end

  private

  def authorize_management(record, query, policy_class: nil)
    Pundit.authorize(current_api_user, record, query, policy_class: policy_class)
  end

  def management_family
    current_api_user.family || raise(ActiveRecord::RecordNotFound)
  end

  def validation_failed(message)
    render json: { error: 'validation_failed', message: message }, status: :unprocessable_content
  end

  def invitation_payload(invitation)
    {
      token: invitation.token,
      email: invitation.email,
      status: invitation.status,
      expires_at: invitation.expires_at.iso8601,
      family: { id: invitation.family_id, name: invitation.family.name },
      acceptance_available: invitation.can_be_accepted? && invitation.family.access_live?
    }
  end
end
