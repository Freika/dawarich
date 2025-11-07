# frozen_string_literal: true

class Family::Invitations::SendingJob < ApplicationJob
  queue_as :families

  def perform(invitation_id)
    invitation = Family::Invitation.find_by(id: invitation_id)

    return unless invitation&.pending?

    FamilyMailer.invitation(invitation).deliver_now
  end
end
