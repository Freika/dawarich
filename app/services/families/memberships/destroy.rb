# frozen_string_literal: true

module Families
  module Memberships
    class Destroy
      attr_reader :user, :member_to_remove, :error_message

      def initialize(user:, member_to_remove: nil)
        @user = user
        @member_to_remove = member_to_remove || user
        @error_message = nil
      end

      def call
        return false unless validate_can_leave

        @family_name = member_to_remove.family.name
        @family_owner = member_to_remove.family.owner

        ActiveRecord::Base.transaction do
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

        @error_message = I18n.t('services.families.memberships.destroy.user_is_not_currently_in_a_family')
        false
      end

      def validate_removal_allowed
        return validate_owner_can_leave if removing_self?

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

        @error_message = I18n.t(
          'services.families.memberships.destroy.family_owners_cannot_remove_their_own_membership_to_leave_the'
        )
        false
      end

      def validate_remover_is_owner
        return true if user.family_owner?

        @error_message = I18n.t('services.families.memberships.destroy.only_family_owners_can_remove_other_members')
        false
      end

      def validate_same_family
        return true if user.family == member_to_remove.family

        @error_message = I18n.t('services.families.memberships.destroy.cannot_remove_members_from_a_different_family')
        false
      end

      def validate_not_removing_owner
        return true unless member_to_remove.family_owner?

        @error_message = I18n.t(
          'services.families.memberships.destroy.cannot_remove_the_family_owner_the_owner_must_delete_the'
        )
        false
      end

      def remove_membership
        member_to_remove.family_membership.destroy!
      end

      def send_notifications
        if removing_self?
          send_self_removal_notifications
        else
          send_member_removed_notifications
        end
      end

      def send_self_removal_notifications
        Notification.create!(
          user: member_to_remove,
          kind: :info,
          title: I18n.t('services.families.memberships.destroy.left_family'),
          content: I18n.t('services.families.memberships.destroy.you_ve_left_the_family_family_name',
                          family_name: @family_name)
        )

        return unless @family_owner&.persisted?

        Notification.create!(
          user: @family_owner,
          kind: :info,
          title: I18n.t('services.families.memberships.destroy.family_member_left'),
          content: I18n.t('services.families.memberships.destroy.email_has_left_the_family_family_name',
                          email: member_to_remove.email, family_name: @family_name)
        )
      end

      def send_member_removed_notifications
        Notification.create!(
          user: member_to_remove,
          kind: :info,
          title: I18n.t('services.families.memberships.destroy.removed_from_family'),
          content: I18n.t('services.families.memberships.destroy.you_have_been_removed_from_the_family_family_name_by',
                          family_name: @family_name, email: user.email)
        )

        return unless user != member_to_remove

        Notification.create!(
          user: user,
          kind: :info,
          title: I18n.t('services.families.memberships.destroy.member_removed'),
          content: I18n.t('services.families.memberships.destroy.email_has_been_removed_from_the_family_family_name',
                          email: member_to_remove.email, family_name: @family_name)
        )
      end

      def handle_record_invalid_error(error)
        @error_message =
          if error.record&.errors&.any?
            error.record.errors.full_messages.first
          else
            I18n.t('services.families.memberships.destroy.failed_to_leave', message: error.message)
          end
      end

      def handle_generic_error(error)
        ExceptionReporter.call(error, "Unexpected error in Families::Memberships::Destroy: #{error.message}")
        @error_message = I18n.t(
          'services.families.memberships.destroy.an_unexpected_error_occurred_while_removing_the_membership_please_try'
        )
      end
    end
  end
end
