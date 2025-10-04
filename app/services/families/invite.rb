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
    rescue ActiveRecord::RecordInvalid => e
      handle_record_invalid_error(e)
      false
    rescue Net::SMTPError => e
      handle_email_error(e)
      false
    rescue StandardError => e
      handle_generic_error(e)
      false
    end

    def error_message
      return errors.full_messages.first if errors.any?
      return @custom_error_message if @custom_error_message

      'Failed to send invitation'
    end

    private

    def invite_sendable?
      unless invited_by.family_owner?
        return add_error_and_false(:invited_by,
                                   'You must be a family owner to send invitations')
      end
      return add_error_and_false(:family, 'Family is full') if family.full?
      return add_error_and_false(:email, 'User is already in a family') if user_already_in_family?
      return add_error_and_false(:email, 'Invitation already sent to this email') if pending_invitation_exists?

      true
    end

    def add_error_and_false(attribute, message)
      errors.add(attribute, message)
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
      # Send email in background with retry logic
      FamilyMailer.invitation(@invitation).deliver_later(
        queue: :mailer,
        retry: 3,
        wait: 30.seconds
      )
    end

    def send_notification
      return unless defined?(Notification)

      Notification.create!(
        user: invited_by,
        kind: :info,
        title: 'Invitation Sent',
        content: "Family invitation sent to #{email}"
      )
    rescue StandardError => e
      # Don't fail the entire operation if notification fails
      Rails.logger.warn "Failed to send invitation notification: #{e.message}"
    end

    def handle_record_invalid_error(error)
      @custom_error_message = if invitation&.errors&.any?
                                invitation.errors.full_messages.first
                              else
                                "Failed to create invitation: #{error.message}"
                              end
    end

    def handle_email_error(error)
      Rails.logger.error "Email delivery failed for family invitation: #{error.message}"
      @custom_error_message = 'Failed to send invitation email. Please try again later'

      # Clean up the invitation if email fails
      invitation&.destroy
    end

    def handle_generic_error(error)
      Rails.logger.error "Unexpected error in Families::Invite: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      @custom_error_message = 'An unexpected error occurred while sending the invitation. Please try again'
    end
  end
end
