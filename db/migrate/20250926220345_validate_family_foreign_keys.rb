# frozen_string_literal: true

class ValidateFamilyForeignKeys < ActiveRecord::Migration[8.0]
  def change
    # No longer needed - foreign keys are now validated immediately in their creation migrations
    # validate_foreign_key :families, :users
    # validate_foreign_key :family_memberships, :families
    # validate_foreign_key :family_memberships, :users
    # validate_foreign_key :family_invitations, :families
    # validate_foreign_key :family_invitations, :users
  end
end
