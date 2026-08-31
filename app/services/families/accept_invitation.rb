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
        @error_message = I18n.t(
          'services.families.accept_invitation.you_must_leave_your_current_family_before_joining_a_new'
        )

        return false
      end

      ActiveRecord::Base.transaction do
        create_membership
        settle_new_member
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
      return false unless validate_family_plan
      return false unless validate_family_capacity

      true
    end

    def validate_invitation
      return true if invitation.can_be_accepted?

      @error_message = I18n.t('services.families.accept_invitation.this_invitation_is_no_longer_valid_or_has_expired')

      false
    end

    def validate_email_match
      return true if invitation.email == user.email

      @error_message = I18n.t('services.families.accept_invitation.this_invitation_is_not_for_your_email_address')

      false
    end

    def validate_family_plan
      return true if DawarichSettings.family_feature_available_for?(invitation.family.owner)

      @error_message = I18n.t('services.families.accept_invitation.this_family_s_plan_is_no_longer_active')

      false
    end

    def validate_family_capacity
      return true unless invitation.family.full?

      @error_message = I18n.t(
        'services.families.accept_invitation.this_family_has_reached_the_maximum_number_of_members'
      )

      false
    end

    def create_membership
      Family::Membership.create!(
        family: invitation.family,
        user: user,
        role: :member
      )
    end

    def settle_new_member
      return if DawarichSettings.self_hosted?

      Families::SyncMembers.new(family: invitation.family).call
    end

    def update_invitation
      invitation.update!(status: :accepted)
    end

    def send_notifications
      send_user_notification
      send_owner_notification
    end

    def send_user_notification
      I18n.with_locale(user.locale) do
        Notification.create!(
          user: user,
          kind: :info,
          title: I18n.t('services.families.accept_invitation.welcome_to_family'),
          content: I18n.t('services.families.accept_invitation.you_ve_joined_the_family_name',
                          name: invitation.family.name)
        )
      end
    end

    def send_owner_notification
      I18n.with_locale(invitation.family.creator.locale) do
        Notification.create!(
          user: invitation.family.creator,
          kind: :info,
          title: I18n.t('services.families.accept_invitation.new_family_member'),
          content: I18n.t('services.families.accept_invitation.email_has_joined_your_family', email: user.email)
        )
      end
    rescue StandardError => e
      ExceptionReporter.call(e, "Unexpected error in Families::AcceptInvitation: #{e.message}")
    end

    def handle_record_invalid_error(error)
      @error_message =
        if error.record&.errors&.any?
          error.record.errors.full_messages.first
        else
          I18n.t('services.families.accept_invitation.failed_to_join', message: error.message)
        end
    end

    def handle_generic_error(error)
      ExceptionReporter.call(error, "Unexpected error in Families::AcceptInvitation: #{error.message}")

      @error_message = I18n.t(
        'services.families.accept_invitation.an_unexpected_error_occurred_while_joining_the_family_please_try'
      )
    end
  end
end
