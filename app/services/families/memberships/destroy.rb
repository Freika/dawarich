# frozen_string_literal: true

module Families
  module Memberships
    class Destroy
      attr_reader :user, :member_to_remove, :error_message

    def initialize(user:, member_to_remove: nil)
      @user = user # The user performing the action (current_user)
      @member_to_remove = member_to_remove || user # The user being removed (defaults to self)
      @error_message = nil
    end

    def call
      return false unless validate_can_leave

      # Store family info before removing membership
      @family_name = member_to_remove.family.name
      @family_owner = member_to_remove.family.owner

      ActiveRecord::Base.transaction do
        handle_ownership_transfer if member_to_remove.family_owner?
        remove_membership
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

    def validate_can_leave
      return false unless validate_in_family
      return false unless validate_removal_allowed

      true
    end

    def validate_in_family
      return true if member_to_remove.in_family?

      @error_message = 'User is not currently in a family.'
      false
    end

    def validate_removal_allowed
      # If removing self (user == member_to_remove)
      if removing_self?
        return validate_owner_can_leave
      end

      # If removing another member, user must be owner and member must be in same family
      return false unless validate_remover_is_owner
      return false unless validate_same_family
      return false unless validate_not_removing_owner

      true
    end

    def removing_self?
      user == member_to_remove
    end

    def validate_owner_can_leave
      return true unless member_to_remove.family_owner?

      @error_message = 'Family owners cannot remove their own membership. To leave the family, delete it instead.'
      false
    end

    def validate_remover_is_owner
      return true if user.family_owner?

      @error_message = 'Only family owners can remove other members.'
      false
    end

    def validate_same_family
      return true if user.family == member_to_remove.family

      @error_message = 'Cannot remove members from a different family.'
      false
    end

    def validate_not_removing_owner
      return true unless member_to_remove.family_owner?

      @error_message = 'Cannot remove the family owner. The owner must delete the family or leave on their own.'
      false
    end

    def family_has_other_members?
      member_to_remove.family.members.count > 1
    end

    def handle_ownership_transfer
      # If this is the last member (owner), delete the family
      return unless member_to_remove.family.members.count == 1

      member_to_remove.family.destroy!

      # If owner tries to leave with other members, it should be prevented in validation
    end

    def remove_membership
      member_to_remove.family_membership.destroy!
    end

    def send_notifications
      return unless defined?(Notification)

      if removing_self?
        send_self_removal_notifications
      else
        send_member_removed_notifications
      end
    end

    def send_self_removal_notifications
      # Notify the user who left
      Notification.create!(
        user: member_to_remove,
        kind: :info,
        title: 'Left Family',
        content: "You've left the family \"#{@family_name}\""
      )

      # Notify the family owner
      return unless @family_owner&.persisted?

      Notification.create!(
        user: @family_owner,
        kind: :info,
        title: 'Family Member Left',
        content: "#{member_to_remove.email} has left the family \"#{@family_name}\""
      )
    end

    def send_member_removed_notifications
      # Notify the member who was removed
      Notification.create!(
        user: member_to_remove,
        kind: :info,
        title: 'Removed from Family',
        content: "You have been removed from the family \"#{@family_name}\" by #{user.email}"
      )

      # Notify the owner who removed the member (if different from the member)
      return unless user != member_to_remove

      Notification.create!(
        user: user,
        kind: :info,
        title: 'Member Removed',
        content: "#{member_to_remove.email} has been removed from the family \"#{@family_name}\""
      )
    end

    def handle_record_invalid_error(error)
      @error_message = if error.record&.errors&.any?
                         error.record.errors.full_messages.first
                       else
                         "Failed to leave family: #{error.message}"
                       end
    end

    def handle_generic_error(error)
      Rails.logger.error "Unexpected error in Families::Memberships::Destroy: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      @error_message = 'An unexpected error occurred while removing the membership. Please try again'
    end
    end
  end
end
