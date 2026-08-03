# frozen_string_literal: true

module Families
  class Create
    include ActiveModel::Validations

    attr_reader :user, :name, :family, :error_message

    validates :name, presence: {
      message: ->(*) { I18n.t('services.families.create.family_name_is_required') }
    }
    validates :name, length: {
      maximum: 50,
      message: ->(*) { I18n.t('services.families.create.family_name_must_be_50_characters_or_less') }
    }

    def initialize(user:, name:)
      @user = user
      @name = name&.strip
      @error_message = nil
    end

    def call
      return false unless valid?
      return false unless validate_user_eligibility
      return false unless validate_feature_access

      ActiveRecord::Base.transaction do
        create_family
        create_owner_membership
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      handle_record_invalid_error(e)

      false
    rescue ActiveRecord::RecordNotUnique => e
      handle_uniqueness_error(e)

      false
    rescue StandardError => e
      handle_generic_error(e)

      false
    end

    private

    def validate_user_eligibility
      if user.in_family?
        @error_message = I18n.t('services.families.create.you_must_leave_your_current_family_before_creating_a_new')
        return false
      end

      if user.created_family.present?
        @error_message = I18n.t('services.families.create.you_have_already_created_a_family_each_user_can_only')
        return false
      end

      true
    end

    def validate_feature_access
      return true if can_create_family?

      # Only reachable on cloud — self-hosted short-circuits in can_create_family?
      @error_message = I18n.t('services.families.create.family_feature_requires_an_active_subscription')

      false
    end

    def can_create_family?
      return true if DawarichSettings.self_hosted?

      user.family?
    end

    def create_family
      @family = Family.create!(name: name, creator: user)
    end

    def create_owner_membership
      Family::Membership.create!(
        family: family,
        user: user,
        role: :owner
      )
    end

    def send_notification
      Notification.create!(
        user: user,
        kind: :info,
        title: I18n.t('services.families.create.family_created'),
        content: I18n.t('services.families.create.you_ve_successfully_created_the_family_name', name: family.name)
      )
    rescue StandardError => e
      # Don't fail the entire operation if notification fails
      ExceptionReporter.call(e, "Unexpected error in Families::Create: #{e.message}")
    end

    def handle_record_invalid_error(error)
      @error_message =
        if family&.errors&.any?
          family.errors.full_messages.first
        else
          I18n.t('services.families.create.failed_to_create_family', message: error.message)
        end
    end

    def handle_uniqueness_error(_error)
      @error_message = I18n.t('services.families.create.a_family_with_this_name_already_exists_for_your_account')
    end

    def handle_generic_error(error)
      ExceptionReporter.call(error, "Unexpected error in Families::Create: #{error.message}")
      @error_message = I18n.t(
        'services.families.create.an_unexpected_error_occurred_while_creating_the_family_please_try'
      )
    end
  end
end
