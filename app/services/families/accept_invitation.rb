# frozen_string_literal: true

module Families
  class AcceptInvitation
    attr_reader :invitation, :user, :error_message

    def initialize(invitation:, user:, auto_leave: false)
      @invitation = invitation
      @user = user
      @auto_leave = auto_leave
      @error_message = nil
    end

    def call
      return false unless can_accept?

      if user.in_family?
        if @auto_leave
          leave_service = Families::Leave.new(user: user)
          unless leave_service.call
            @error_message = leave_service.error_message || 'Failed to leave current family.'
            return false
          end
        else
          @error_message = 'You must leave your current family before joining a new one.'
          return false
        end
      end

      ActiveRecord::Base.transaction do
        create_membership
        update_invitation
        send_notifications
      end

      true
    rescue ActiveRecord::RecordInvalid
      @error_message = 'Failed to join family due to validation errors.'
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
      return true if invitation.family.members.count < Family::MAX_MEMBERS

      @error_message = 'This family has reached the maximum number of members.'
      false
    end

    def create_membership
      FamilyMembership.create!(
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
      Notification.create!(
        user: invitation.family.creator,
        kind: :info,
        title: 'New Family Member',
        content: "#{user.email} has joined your family"
      )
    end
  end
end
