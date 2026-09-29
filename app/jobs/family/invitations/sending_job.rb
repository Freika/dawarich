# frozen_string_literal: true

class Family::Invitations::SendingJob < ApplicationJob
  queue_as :families

  OWNERSHIP_KEY = 'command:mail.family_invitation'

  def perform(invitation_id)
    return forward(invitation_id) if JobOwnership.lock_owner(OWNERSHIP_KEY) == :oban

    invitation = Family::Invitation.find_by(id: invitation_id)

    return unless invitation&.pending?

    FamilyMailer.invitation(invitation).deliver_now
  end

  private

  def forward(invitation_id)
    JobCommands.forward('mail.family_invitation', { 'invitation_id' => invitation_id, 'locale' => I18n.locale.to_s },
                        event_id: job_id, aggregate_id: invitation_id, producer: self.class.name,
                        dedupe_key: "family-invitation:#{invitation_id}")
  end
end
