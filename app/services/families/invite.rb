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
        invitation = create_invitation
        send_invitation_email(invitation)
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

      I18n.t('services.families.invite.failed_to_send_invitation')
    end

    private

    def invite_sendable?
      unless invited_by.family_owner?
        return add_error_and_false(:invited_by,
                                   I18n.t('services.families.invite.owner_required'))
      end
      return add_error_and_false(:family, I18n.t('services.families.invite.family_full')) if family.full?
      if user_already_in_family?
        return add_error_and_false(:email, I18n.t('services.families.invite.user_already_in_family'))
      end
      if pending_invitation_exists?
        return add_error_and_false(:email, I18n.t('services.families.invite.invitation_already_sent'))
      end

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
      @invitation = Family::Invitation.create!(
        family: family,
        email: email,
        invited_by: invited_by
      )
    end

    def send_invitation_email(invitation)
      Family::Invitations::SendingJob.perform_later(invitation.id)
    end

    def send_notification
      content = I18n.t(
        DawarichSettings.self_hosted? ? 'services.families.invite.sent_self_hosted' : 'services.families.invite.sent',
        email:
      )

      I18n.with_locale(invited_by.locale) do
        Notification.create!(
          user: invited_by,
          kind: :info,
          title: I18n.t('services.families.invite.invitation_sent'),
          content: content
        )
      end
    rescue StandardError => e
      # Don't fail the entire operation if notification fails
      ExceptionReporter.call(e, "Unexpected error in Families::Invite: #{e.message}")
    end

    def handle_record_invalid_error(error)
      @custom_error_message = if invitation&.errors&.any?
                                invitation.errors.full_messages.first
                              else
                                I18n.t('services.families.invite.failed_to_create', message: error.message)
                              end
    end

    def handle_email_error(error)
      Rails.logger.error "Email delivery failed for family invitation: #{error.message}"
      @custom_error_message = I18n.t('services.families.invite.failed_to_send_invitation_email_please_try_again_later')

      # Clean up the invitation if email fails
      invitation&.destroy
    end

    def handle_generic_error(error)
      ExceptionReporter.call(error, "Unexpected error in Families::Invite: #{error.message}")
      @custom_error_message = I18n.t(
        'services.families.invite.an_unexpected_error_occurred_while_sending_the_invitation_please_try'
      )
    end
  end
end
