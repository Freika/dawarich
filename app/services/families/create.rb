# frozen_string_literal: true

module Families
  class Create
    attr_reader :user, :name, :family

    def initialize(user:, name:)
      @user = user
      @name = name
    end

    def call
      return false if user.in_family?
      return false unless can_create_family?

      ActiveRecord::Base.transaction do
        create_family
        create_owner_membership
      end

      true
    rescue ActiveRecord::RecordInvalid
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
