# frozen_string_literal: true

# A pending invitation as the Family owner sees it. The serializer has no
# request, so the caller passes `request.base_url` to build the shareable link.
class Api::FamilyInvitationSerializer
  def self.pending_for(family, base_url:)
    family.family_invitations.active.order(:created_at).map { |invitation| new(invitation, base_url:).call }
  end

  def initialize(invitation, base_url:)
    @invitation = invitation
    @base_url = base_url
  end

  def call
    {
      id: invitation.id,
      email: invitation.email,
      created_at: invitation.created_at.iso8601,
      expires_at: invitation.expires_at.iso8601,
      url: base_url + Rails.application.routes.url_helpers.public_invitation_path(invitation.token)
    }
  end

  private

  attr_reader :invitation, :base_url
end
