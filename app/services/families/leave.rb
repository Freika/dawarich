# frozen_string_literal: true

module Families
  class Leave
    attr_reader :user, :error_message

    def initialize(user:)
      @user = user
      @error_message = nil
    end

    def call
      return false unless validate_can_leave

      ActiveRecord::Base.transaction do
        handle_ownership_transfer if user.family_owner?
        remove_membership
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid
      @error_message = 'Failed to leave family due to validation errors.'
      false
    end

    private

    def validate_can_leave
      return false unless validate_in_family
      return false unless validate_owner_can_leave

      true
    end

    def validate_in_family
      return true if user.in_family?

      @error_message = 'You are not currently in a family.'
      false
    end

    def validate_owner_can_leave
      return true unless user.family_owner? && family_has_other_members?

      @error_message = 'You cannot leave the family while you are the owner and there are ' \
                       'other members. Remove all members first or transfer ownership.'
      false
    end

    def family_has_other_members?
      user.family.members.count > 1
    end

    def handle_ownership_transfer
      # If this is the last member (owner), delete the family
      return unless user.family.members.count == 1

      user.family.destroy!

      # If owner tries to leave with other members, it should be prevented in validation
    end

    def remove_membership
      user.family_membership.destroy!
    end

    def send_notification
      Notification.create!(
        user: user,
        kind: :info,
        title: 'Left Family',
        content: "You've left the family"
      )
    end
  end
end
