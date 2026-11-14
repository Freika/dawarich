# frozen_string_literal: true

# No coordinates or sharing controls belong in membership administration.
class Api::FamilyManagementSerializer
  def initialize(user)
    @user = user
  end

  def call
    family = @user.family
    membership = @user.family_membership
    {
      self_hosted: DawarichSettings.self_hosted?,
      feature_enabled: @user.feature_enabled?(:family),
      entitled: DawarichSettings.family_feature_available_for?(@user),
      family: family && { id: family.id, name: family.name, access_live: family.access_live? },
      me: membership && { membership_id: membership.id, user_id: @user.id, owner: membership.owner? },
      capacity: {
        limit: DawarichSettings.self_hosted? ? nil : Family::MAX_MEMBERS,
        members: family ? family.members.count : 0,
        pending_invitations: family ? family.family_invitations.active.count : 0
      },
      members: member_rows(family, membership)
    }
  end

  private

  def member_rows(family, membership)
    return [] unless membership

    # Even after lapse an owner needs a roster to remove members. Other members
    # only need their own membership to leave; do not expose the lapsed roster.
    memberships = membership.owner? ? family.family_memberships.includes(:user).order(:id) : [membership]
    memberships.map do |row|
      { id: row.id, user_id: row.user_id, name: row.user.display_name, role: row.role }
    end
  end
end
