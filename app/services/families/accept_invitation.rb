# frozen_string_literal: true

module Families
  class AcceptInvitation
    attr_reader :invitation, :user, :error_message

    def initialize(invitation:, user:)
      @invitation = invitation
      @user = user
      @error_message = nil
    end

    def call
      return false unless can_accept?

      if user.in_family?
        @error_message = 'You must leave your current family before joining a new one.'
        return false
      end

      ActiveRecord::Base.transaction do
        create_membership
        update_invitation
        send_notifications
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      handle_record_invalid_error(e)
      false
    rescue StandardError => e
      handle_generic_error(e)
      false
    end

    private

    def can_accept?
      return false unless validate_invitation
      return false unless validate_email_match
      return false unless validate_family_capacity

      true
    end

    def validate_invitation
      return true if invitation.can_be_accepted?

      @error_message = 'This invitation is no longer valid or has expired.'
      false
    end

    def validate_email_match
      return true if invitation.email == user.email

      @error_message = 'This invitation is not for your email address.'
      false
    end

    def validate_family_capacity
      return true unless invitation.family.full?

      @error_message = 'This family has reached the maximum number of members.'
      false
    end

    def create_membership
      Family::Membership.create!(
        family: invitation.family,
        user: user,
        role: :member
      )
    end

    def update_invitation
      invitation.update!(status: :accepted)
    end

    def send_notifications
      send_user_notification
      send_owner_notification
    end

    def send_user_notification
      Notification.create!(
        user: user,
        kind: :info,
        title: 'Welcome to Family',
        content: "You've joined the family '#{invitation.family.name}'"
      )
    end

    def send_owner_notification
      return unless defined?(Notification)

      Notification.create!(
        user: invitation.family.creator,
        kind: :info,
        title: 'New Family Member',
        content: "#{user.email} has joined your family"
      )
    rescue StandardError => e
      # Don't fail the entire operation if notification fails
      Rails.logger.warn "Failed to send family join notification: #{e.message}"
    end

    def handle_record_invalid_error(error)
      @error_message = if error.record&.errors&.any?
                         error.record.errors.full_messages.first
                       else
                         "Failed to join family: #{error.message}"
                       end
    end

    def handle_generic_error(error)
      Rails.logger.error "Unexpected error in Families::AcceptInvitation: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      @error_message = 'An unexpected error occurred while joining the family. Please try again'
    end
  end
end
