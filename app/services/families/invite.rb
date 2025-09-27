# frozen_string_literal: true

module Families
  class Invite
    include ActiveModel::Validations

    attr_reader :family, :email, :invited_by, :invitation, :errors

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

    def initialize(family:, email:, invited_by:)
      @family = family
      @email = email.downcase.strip
      @invited_by = invited_by
      @errors = {}
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
    rescue ActiveRecord::RecordInvalid => e
      @errors[:base] = e.message
      false
    end

    def error_message
      return errors.values.first if errors.any?
      return validation_error_message unless valid?

      'Failed to send invitation'
    end

    private

    def validation_error_message
      errors.full_messages.first || 'Invalid invitation data'
    end

    def invite_sendable?
      return add_error_and_false(:invited_by, 'You must be a family owner to send invitations') unless invited_by.family_owner?
      return add_error_and_false(:family, 'Family is full') if family.members.count >= Family::MAX_MEMBERS
      return add_error_and_false(:email, 'User is already in a family') if user_already_in_family?
      return add_error_and_false(:email, 'Invitation already sent to this email') if pending_invitation_exists?

      true
    end

    def add_error_and_false(attribute, message)
      @errors[attribute] = message
      false
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