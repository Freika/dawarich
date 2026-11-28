# frozen_string_literal: true

class Api::FamilySerializer
  def initialize(user, base_url:)
    @user = user
    @base_url = base_url
  end

  def call
    {
      lapsed: false,
      history_before_sharing_supported: true,
      family: { name: family.name },
      me: me_payload,
      members: members_payload,
      location_requests: {
        incoming: user.received_location_requests.active.includes(:requester).map do |request|
          incoming_request(request)
        end,
        outgoing: user.sent_location_requests.active.map { |request| outgoing_request(request) }
      },
      seats: seats_payload,
      can_invite: user.family_owner? && family.can_add_members?
    }.merge(owner_payload)
  end

  private

  attr_reader :user, :base_url

  def family
    user.family
  end

  def me_payload
    {
      user_id: user.id,
      owner: user.family_owner?,
      sharing: {
        enabled: user.family_sharing_enabled?,
        duration: user.family_sharing_duration,
        expires_at: user.family_sharing_expires_at&.iso8601,
        started_at: user.family_sharing_started_at&.iso8601,
        share_history: user.family_share_history?,
        history_window: user.family_history_window,
        history_before_sharing: user.family_history_before_sharing?
      },
      inherits_plan: inherits_plan?
    }
  end

  # The condition under which Family::Membership#revoke_inherited_subscription
  # downgrades the account when its holder leaves.
  def inherits_plan?
    !DawarichSettings.self_hosted? && !user.family_owner? && user.sub_source_none?
  end

  def seats_payload
    {
      limit: DawarichSettings.self_hosted? ? nil : Family::MAX_MEMBERS,
      members: family.member_count,
      pending: family.pending_invitations_count
    }
  end

  # Invitation links let anyone holding them join, so only the owner gets them.
  def owner_payload
    return {} unless user.family_owner?

    { invitations: Api::FamilyInvitationSerializer.pending_for(family, base_url:) }
  end

  def members_payload
    family.members.includes(:family_membership).map do |member|
      history_shared = member.family_sharing_enabled? && member.family_share_history?
      {
        user_id: member.id,
        email: member.email,
        name: member.display_name,
        email_initial: member.email.first.upcase,
        owner: member.family_owner?,
        sharing_enabled: member.family_sharing_enabled?,
        share_history: history_shared,
        history_window: history_shared ? member.family_history_window : nil,
        history_before_sharing: member.family_history_before_sharing?,
        sharing_started_at: member.family_sharing_started_at&.iso8601,
        joined_at: member.family_membership.created_at.iso8601
      }
    end
  end

  def incoming_request(request)
    {
      id: request.id,
      requester: { user_id: request.requester_id, email: request.requester.email },
      suggested_duration: request.suggested_duration,
      expires_at: request.expires_at.iso8601,
      created_at: request.created_at.iso8601
    }
  end

  def outgoing_request(request)
    {
      id: request.id,
      target_user_id: request.target_user_id,
      created_at: request.created_at.iso8601
    }
  end
end
