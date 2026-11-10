# frozen_string_literal: true

class Api::V1::Families::InvitationsController < Api::V1::Families::BaseController
  include Api::FamilyErrorRendering

  # #destroy stays open to a lapsed owner so pending invitations can still be
  # revoked. #preview and #accept are for users who are not in a family yet, and
  # skip the payment gate: a Cloud account made through Apple or Google sign-in
  # is pending_payment until it joins, and joining is what activates it.
  skip_before_action :ensure_family_feature_available!, only: %i[destroy preview accept]
  skip_before_action :ensure_user_in_family!, only: %i[preview accept]
  skip_before_action :reject_pending_payment!, only: %i[preview accept]
  before_action :ensure_family_owner!, only: %i[create destroy]
  before_action :ensure_family_toggle_on!, :set_invitation_by_token, only: %i[preview accept]

  # Each invitation sends an email, and revoke-then-invite is otherwise unbounded.
  rate_limit to: 10, within: 1.hour, only: :create, by: -> { current_api_user.id },
             with: -> { render_family_error(:rate_limited) },
             unless: -> { DawarichSettings.self_hosted? }

  def create
    family = current_api_user.family
    service = Families::Invite.new(family: family, email: string_param(:email), invited_by: current_api_user)
    return render_family_service_error(service) unless service.call

    render json: { invitation: invitation_json(service.invitation) }, status: :created
  end

  def destroy
    family = current_api_user.family
    # Under the family lock a concurrent accept cannot overwrite the revoke.
    cancelled = family.with_lock do
      invitation = family.family_invitations.active.find_by(id: params[:id])
      invitation&.update!(status: :cancelled)
    end
    return render_family_error(:invitation_not_found) unless cancelled

    head :no_content
  end

  def preview
    return render_family_error(:invitation_invalid) unless @invitation.can_be_accepted?

    render json: { invitation: preview_json }
  end

  def accept
    service = Families::AcceptInvitation.new(invitation: @invitation, user: current_api_user)
    return render_family_service_error(service) unless service.call

    render json: Api::FamilySerializer.new(current_api_user.reload).call
  end

  private

  # Missing or non-string values become '', so they fail as a coded refusal
  # instead of raising inside the service.
  def string_param(key)
    params[key].is_a?(String) ? params[key] : ''
  end

  def ensure_family_owner!
    policy = FamilyPolicy.new(current_api_user, current_api_user.family)
    allowed = action_name == 'create' ? policy.invite? : policy.manage_invitations?
    return if allowed

    render_family_error(:owner_required)
  end

  def ensure_family_toggle_on!
    return if current_api_user.feature_enabled?(:family)

    render_family_error(:feature_disabled, I18n.t('controllers.application.feature_disabled_in_settings'))
  end

  def set_invitation_by_token
    token = string_param(:token)
    @invitation = Family::Invitation.find_by(token: token) if token.present?
    render_family_error(:invitation_not_found) unless @invitation
  end

  def invitation_json(invitation)
    Api::FamilyInvitationSerializer.new(invitation, base_url: request.base_url).call
  end

  def preview_json
    {
      family_name: @invitation.family.name,
      invited_by_email: @invitation.invited_by.email,
      email: @invitation.email,
      expires_at: @invitation.expires_at.iso8601,
      plan_active: @invitation.family.access_live?,
      email_matches: @invitation.email == current_api_user.email
    }
  end
end
