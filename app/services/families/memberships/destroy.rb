# frozen_string_literal: true

module Families
  module Memberships
    class Destroy
      attr_reader :user, :member_to_remove, :error_message, :error_code

      def initialize(user:, member_to_remove: nil)
        @user = user
        @member_to_remove = member_to_remove || user
        @error_message = nil
      end

      def call
        return false unless validate_can_leave

        membership = member_to_remove.family_membership
        family = membership.family
        @family_name = family.name
        @family_owner = family.owner

        # Family first, then users: the lock order of every other writer to a
        # family. Without it a removal can deadlock with a concurrent accept.
        family.with_lock { remove(membership) }
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

        refuse(:not_in_family, 'user_is_not_currently_in_a_family')
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

        refuse(:owner_cannot_leave, 'family_owners_cannot_remove_their_own_membership_to_leave_the')
        false
      end

      def validate_remover_is_owner
        return true if user.family_owner?

        refuse(:owner_required, 'only_family_owners_can_remove_other_members')
        false
      end

      def validate_same_family
        return true if user.family == member_to_remove.family

        refuse(:member_not_found, 'cannot_remove_members_from_a_different_family')
        false
      end

      def validate_not_removing_owner
        return true unless member_to_remove.family_owner?

        refuse(:cannot_remove_owner, 'cannot_remove_the_family_owner_the_owner_must_delete_the')
        false
      end

      def refuse(code, message_key)
        @error_code = code
        @error_message = I18n.t("services.families.memberships.destroy.#{message_key}")
      end

      # A second request for the same member may have removed it while this
      # one waited for the lock.
      def remove(membership)
        unless Family::Membership.exists?(membership.id)
          refuse(removing_self? ? :not_in_family : :member_not_found, 'user_is_not_currently_in_a_family')
          return false
        end

        membership.destroy!
        send_notifications
        true
      end

      def send_notifications
        if removing_self?
          send_self_removal_notifications
        else
          send_member_removed_notifications
        end
      end

      # Only the person who did not act is notified; the one who left or
      # removed someone is told by the page.
      def send_self_removal_notifications
        return unless @family_owner&.persisted?

        I18n.with_locale(@family_owner.locale) do
          Notifications::Create.new(
            user: @family_owner,
            kind: :info,
            title: I18n.t('services.families.memberships.destroy.family_member_left'),
            content: I18n.t('services.families.memberships.destroy.email_has_left_the_family_family_name',
                            email: member_to_remove.email, family_name: @family_name),
            action_path: Notifications.paths.family_path
          ).call
        end
      end

      # No action_path: the removed member has no family page any more.
      def send_member_removed_notifications
        I18n.with_locale(member_to_remove.locale) do
          Notifications::Create.new(
            user: member_to_remove,
            kind: :info,
            title: I18n.t('services.families.memberships.destroy.removed_from_family'),
            content: I18n.t(
              'services.families.memberships.destroy.you_have_been_removed_from_the_family_family_name_by',
              family_name: @family_name, email: user.email
            )
          ).call
        end
      end

      def handle_record_invalid_error(error)
        @error_code = :unexpected_error
        @error_message =
          if error.record&.errors&.any?
            error.record.errors.full_messages.first
          else
            I18n.t('services.families.memberships.destroy.failed_to_leave', message: error.message)
          end
      end

      def handle_generic_error(error)
        @error_code = :unexpected_error
        ExceptionReporter.call(error, "Unexpected error in Families::Memberships::Destroy: #{error.message}")
        @error_message = I18n.t(
          'services.families.memberships.destroy.an_unexpected_error_occurred_while_removing_the_membership_please_try'
        )
      end
    end
  end
end
