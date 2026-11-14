# frozen_string_literal: true

# A user whose Membership survives but whose Entitlement has gone. The payload
# carries only what is needed to explain the state — the family's name and
# whether this user is the Family owner, so the client can offer renewal to the
# one person who can act on it. Member identities and locations are deliberately
# absent: a lapsed user has no entitlement to them. The owner is the exception:
# they get the other members' emails and the pending invitations, as on the web
# lapsed page, so they can remove members, revoke invitations and dissolve the
# family without renewing first.
class Api::LapsedFamilySerializer
  def initialize(user, base_url:)
    @user = user
    @base_url = base_url
  end

  def call
    {
      lapsed: true,
      family: { name: user.family&.name },
      me: {
        user_id: user.id,
        owner: user.family_owner?
      }
    }.merge(owner_payload)
  end

  private

  attr_reader :user, :base_url

  def owner_payload
    return {} unless user.family_owner? && user.family

    {
      members: other_members.map do |member|
        { user_id: member.id, email: member.email, email_initial: member.email.first.upcase,
          owner: member.family_owner? }
      end,
      invitations: Api::FamilyInvitationSerializer.pending_for(user.family, base_url:)
    }
  end

  def other_members
    user.family.members.includes(:family_membership).where.not(id: user.id).order(:id)
  end
end
