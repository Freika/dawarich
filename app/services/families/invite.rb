# frozen_string_literal: true

module Families
  class Invite
    include ActiveModel::Validations

    attr_reader :family, :email, :invited_by, :invitation

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

    def initialize(family:, email:, invited_by:)
      @family = family
      @email = email.downcase.strip
      @invited_by = invited_by
    end

    def call
      return false unless valid?
      return false unless invite_sendable?

      ActiveRecord::Base.transaction do
        create_invitation
        send_invitation_email
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    private

    def invite_sendable?
      return false unless invited_by.family_owner?
      return false if family.members.count >= Family::MAX_MEMBERS
      return false if user_already_in_family?
      return false if pending_invitation_exists?

      true
    end

    def user_already_in_family?
      User.joins(:family_membership)
          .where(email: email)
          .exists?
    end

    def pending_invitation_exists?
      family.family_invitations.active.where(email: email).exists?
    end

    def create_invitation
      @invitation = FamilyInvitation.create!(
        family: family,
        email: email,
        invited_by: invited_by
      )
    end

    def send_invitation_email
      FamilyMailer.invitation(@invitation).deliver_later
    end

    def send_notification
      Notification.create!(
        user: invited_by,
        kind: :info,
        title: 'Invitation Sent',
        content: "Family invitation sent to #{email}"
      )
    end
  end
end
