# frozen_string_literal: true

class Api::FamilySerializer
  def initialize(user)
    @user = user
  end

  def call
    {
      lapsed: false,
      family: { name: family.name },
      me: me_payload,
      members: members_payload,
      location_requests: {
        incoming: user.received_location_requests.active.includes(:requester).map do |request|
          incoming_request(request)
        end,
        outgoing: user.sent_location_requests.active.map { |request| outgoing_request(request) }
      }
    }
  end

  private

  attr_reader :user

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
        history_window: user.family_history_window
      }
    }
  end

  def members_payload
    family.members.includes(:family_membership).map do |member|
      {
        user_id: member.id,
        email: member.email,
        email_initial: member.email.first.upcase,
        owner: member.family_owner?,
        sharing_enabled: member.family_sharing_enabled?,
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
