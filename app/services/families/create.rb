# frozen_string_literal: true

module Families
  class Create
    attr_reader :user, :name, :family, :errors

    def initialize(user:, name:)
      @user = user
      @name = name
      @errors = {}
    end

    def call
      if user.in_family?
        @errors[:user] = 'User is already in a family'
        return false
      end

      unless can_create_family?
        @errors[:base] = 'Cannot create family'
        return false
      end

      ActiveRecord::Base.transaction do
        create_family
        create_owner_membership
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      if @family&.errors&.any?
        @family.errors.each { |attribute, message| @errors[attribute] = message }
      else
        @errors[:base] = e.message
      end
      false
    end

    private

    def can_create_family?
      return true if DawarichSettings.self_hosted?

      # TODO: Add cloud plan validation here when needed
      # For now, allow all users to create families
      true
    end

    def create_family
      @family = Family.create!(name:, creator: user)
    end

    def create_owner_membership
      FamilyMembership.create!(
        family: family,
        user: user,
        role: :owner
      )
    end
  end
end
