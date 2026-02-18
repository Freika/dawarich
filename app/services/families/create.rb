# frozen_string_literal: true

module Families
  class Create
    include ActiveModel::Validations

    attr_reader :user, :name, :family, :error_message

    validates :name, presence: { message: 'Family name is required' }
    validates :name, length: {
      maximum: 50,
      message: 'Family name must be 50 characters or less'
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
        @error_message = 'You must leave your current family before creating a new one'
        return false
      end

      if user.created_family.present?
        @error_message = 'You have already created a family. Each user can only create one family'
        return false
      end

      true
    end

    def validate_feature_access
      return true if can_create_family?

      @error_message = 'Family feature requires a Family plan'

      false
    end

    def can_create_family?
      @user.family_feature_available?
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
        title: 'Family Created',
        content: "You've successfully created the family '#{family.name}'"
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
          "Failed to create family: #{error.message}"
        end
    end

    def handle_uniqueness_error(_error)
      @error_message = 'A family with this name already exists for your account'
    end

    def handle_generic_error(error)
      ExceptionReporter.call(error, "Unexpected error in Families::Create: #{error.message}")
      @error_message = 'An unexpected error occurred while creating the family. Please try again'
    end
  end
end
